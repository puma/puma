# Fork-Worker Cluster Mode [Experimental]

`fork_worker` (`--fork-worker` from the CLI) is an experimental cluster-mode configuration option. This mode causes Puma to fork additional workers from worker 0, instead of directly from the master process.

```
10000   \_ puma 8.0.2 (tcp://0.0.0.0:9292) [puma]
10001       \_ puma: cluster worker 0: 10000 [puma]
10002           \_ puma: cluster worker 1: 10000 [puma]
10003           \_ puma: cluster worker 2: 10000 [puma]
10004           \_ puma: cluster worker 3: 10000 [puma]
```

The `fork_worker` option allows your application to be initialized only once for copy-on-write memory savings, and it has two additional advantages:

1. **Compatible with phased restart.** With `preload_app!` disabled, the master process doesn't load the application, so this mode works with phased restart (`SIGUSR1` or `pumactl phased-restart`). When worker 0 reloads as part of a phased restart, it initializes a new copy of your application first, then the other workers reload by forking from this new worker already containing the new preloaded application.

   This allows a phased restart to complete as quickly as a hot restart (`SIGUSR2` or `pumactl restart`), while still minimizing downtime by staggering the restart across cluster workers.

2. **'Refork' for additional copy-on-write improvements in running applications.** Fork-worker mode introduces a new `refork` command that re-loads all nonzero workers by re-forking them from worker 0.

   This command can potentially improve memory utilization in large or complex applications that don't fully pre-initialize on startup, because the re-forked workers can share copy-on-write memory with a worker that has been running for a while and serving requests.

   You can trigger a refork by sending the cluster the `SIGURG` signal or running the `pumactl refork` command at any time. A refork will also automatically trigger once, after a certain number of requests have been processed by worker 0 (default 1000). To configure the number of requests before the auto-refork, pass a positive integer argument to `fork_worker` (e.g., `fork_worker 1000`), or `0` to disable.

### Usage Considerations

- `fork_worker` introduces new `before_refork` and `after_refork` configuration hooks. Note the following:
    - When initially forking the parent process to the worker 0 child, `before_fork` will trigger on the parent process and `before_worker_boot` will trigger on the worker 0 child as normal.
    - When forking the worker 0 child to grandchild workers, `before_refork` and `after_refork` will trigger on the worker 0 child, and `before_worker_boot` will trigger on each grandchild worker.
    - For clarity, `before_fork` does not trigger on worker 0, and `after_refork` does not trigger on the grandchild.
- As a general migration guide:
    - Copy any logic within your existing `before_fork` hook to the `before_refork` hook.
    - Consider copying logic from your `before_worker_boot` hook to the `after_refork` hook, if it is needed to reset the state of worker 0 after it forks.

### Limitations

- This mode is still very experimental so there may be bugs or edge-cases, particularly around expected behavior of existing hooks. Please open a [bug report](https://github.com/puma/puma/issues/new?template=bug_report.md) if you encounter any issues.

- In order to fork new workers cleanly, worker 0 shuts down its server and stops serving requests so there are no open file descriptors or other kinds of shared global state between processes, and to maximize copy-on-write efficiency across the newly-forked workers. This may temporarily reduce total capacity of the cluster during a phased restart / refork.

- In a cluster with `n` workers, a normal phased restart stops and restarts workers one by one while the application is loaded in each process, so `n-1` workers are available serving requests during the restart. In a phased restart in fork-worker mode, the application is first loaded in worker 0 while `n-1` workers are available, then worker 0 remains stopped while the rest of the workers are reloaded one by one, leaving only `n-2` workers to be available for a brief period of time. Reloading the rest of the workers should be quick because the application is preloaded at that point, but there may be situations where it can take longer (slow clients, long-running application code, slow worker-fork hooks, etc).

# Mold-Worker Cluster Mode [Experimental]

`mold_worker` (`--mold-worker` from the CLI) is an alternative to `fork_worker`. Instead of forking from a worker that also serves requests, Puma promotes a worker to a "mold", which stops serving requests and only forks new workers. Because the mold never serves traffic, a slow request, timeout or memory limit can't take it down mid-refork.

```
10000   \_ puma 8.0.2 (tcp://0.0.0.0:9292) [puma]
10005       \_ puma: mold 2: 10000 [puma]
10011           \_ puma: cluster worker 0: 10000 [puma]
10012           \_ puma: cluster worker 1: 10000 [puma]
10013           \_ puma: cluster worker 2: 10000 [puma]
```

Workers are forked from the master at boot. Each request threshold (default `1000`) promotes the busiest worker to a new mold, retires the previous one, and reforks every worker from the new mold.

```ruby
mold_worker 1000, 2000, 4000
```

### Usage Considerations

- Thresholds are per worker, counted from when that worker booted. Workers forked from a mold start again at zero, so with the config above a worker is promoted after 1000 requests, and a worker from that generation is promoted after another 2000.
- After the last threshold, molds are only replaced by `SIGURG` or `pumactl refork`, which promote the busiest worker at any time.
- A phased restart (`SIGUSR1` or `pumactl phased-restart`) retires the mold and forks workers from the master, so new code is loaded, then starts the thresholds again. As with any phased restart, this requires `preload_app!` to be disabled.
- `mold_worker` cannot be combined with `fork_worker`.
- On Linux 3.4+, workers are reparented to the master rather than orphaned if their mold exits.
- `mold_worker` introduces new `after_mold_promotion` and `before_mold_shutdown` configuration hooks.
    - `after_mold_promotion` runs in the mold after it stops serving requests, before it forks any workers. Use it for what you would do in `before_refork`, such as closing connections or running garbage collection.
    - `before_mold_shutdown` runs in the mold before it exits.
    - `before_worker_boot` runs in each forked worker, as usual. Use it for what you would do in `after_refork`.
