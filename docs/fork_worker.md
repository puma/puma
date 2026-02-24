# Fork-Worker Cluster Mode [Experimental]

Puma 5 introduces an experimental new cluster-mode configuration option, `fork_worker` (`--fork-worker` from the CLI). This mode causes Puma to fork additional workers from worker 0, instead of directly from the master process:

```
10000   \_ puma 4.3.3 (tcp://0.0.0.0:9292) [puma]
10001       \_ puma: cluster worker 0: 10000 [puma]
10002           \_ puma: cluster worker 1: 10000 [puma]
10003           \_ puma: cluster worker 2: 10000 [puma]
10004           \_ puma: cluster worker 3: 10000 [puma]
```

The `fork_worker` option allows your application to be initialized only once for copy-on-write memory savings, and it has two additional advantages:

1. **Compatible with phased restart.** Because the master process itself doesn't preload the application, this mode works with phased restart (`SIGUSR1` or `pumactl phased-restart`). When worker 0 reloads as part of a phased restart, it initializes a new copy of your application first, then the other workers reload by forking from this new worker already containing the new preloaded application.

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
    - Consider to copy logic from your `before_worker_boot` hook to the `after_refork` hook, if it is needed to reset the state of worker 0 after it forks.

### Limitations

- This mode is still very experimental so there may be bugs or edge-cases, particularly around expected behavior of existing hooks. Please open a [bug report](https://github.com/puma/puma/issues/new?template=bug_report.md) if you encounter any issues.

- In order to fork new workers cleanly, worker 0 shuts down its server and stops serving requests so there are no open file descriptors or other kinds of shared global state between processes, and to maximize copy-on-write efficiency across the newly-forked workers. This may temporarily reduce total capacity of the cluster during a phased restart / refork.

- In a cluster with `n` workers, a normal phased restart stops and restarts workers one by one while the application is loaded in each process, so `n-1` workers are available serving requests during the restart. In a phased restart in fork-worker mode, the application is first loaded in worker 0 while `n-1` workers are available, then worker 0 remains stopped while the rest of the workers are reloaded one by one, leaving only `n-2` workers to be available for a brief period of time. Reloading the rest of the workers should be quick because the application is preloaded at that point, but there may be situations where it can take longer (slow clients, long-running application code, slow worker-fork hooks, etc).

### PR_SET_CHILD_SUBREAPER

Where available from the OS (Linux ), if you are using `fork_worker` Puma will mark the cluster parent automatically as a "child subreaper", so that in case worker-0 terminates, its child processes end up reparented to the cluster parent rather than orphaned. 

### Mold-Worker Cluster Mode [Experimental] [Alternative]

`mold_worker` is similar in concept to `fork_worker` except that before a worker-0 process reforks, it permanently stops handling requests and converts to a "mold" process, effectively an idle worker template. This provides some stability advantages over the standard fork_worker mode, as you no longer have to coordinate reforks with a request server stopping and restarting, and are at much lower risk of losing the reforking process to termination via OOM, timeouts, or other external mechanisms.

### Mold-Worker Important Differences

- **Request-count thresholds are per-worker.** Each threshold is checked against the individual worker's `requests_count`, which counts requests served since that worker was booted (or re-forked). When any worker crosses the next threshold, it is promoted to a mold and a cluster-wide phased refork begins. Workers forked from the new mold start with a fresh `requests_count` of 0 -- they do *not* inherit the mold's count.
- `mold_worker` is capable of reforking at multiple intervals; by default it will trigger one mold promotion and a phased refork at 1000 requests, but you can pass 1..n intervals instead and it will trigger a refork as it passes each (e.g., `mold_worker 1000, 5000, 25000`).
- `mold_worker` will, at boot and during phased restart via USR1, fork all worker processes directly from the cluster parent; molds at this point are just a memory cost with no benefit.
- Mold processes will _not_ become more efficient over time as they have stopped taking traffic; to see additional benefits, add an additional refork interval at the end to promote a new more complete mold, or use SIGURG to promote whatever worker has the highest request count to mold and replace all the other workers with reforks.

### Mold-Worker Hook Mapping

The table below maps `fork_worker` hooks to their `mold_worker` equivalents:

| `fork_worker` hook | `mold_worker` equivalent | Notes |
|---|---|---|
| `before_refork` (`on_refork`) | `on_mold_promotion` | Resource cleanup before forking. In `fork_worker`, worker 0 briefly stops serving to refork; in `mold_worker`, the promoted worker permanently stops serving, so cleanup is final. |
| `after_refork` | *(no equivalent)* | In `fork_worker`, worker 0 resumes serving after the refork cycle. Molds never resume, so there is nothing to re-establish. Use `before_worker_boot` (`on_worker_boot`) in the new workers instead if you need to set up connections. |
| `before_worker_boot` (`on_worker_boot`) | `before_worker_boot` (`on_worker_boot`) | Unchanged -- runs in each newly-forked worker (whether forked from worker 0 or from a mold). |
| `before_worker_shutdown` (`on_worker_shutdown`) | `before_worker_shutdown` (`on_worker_shutdown`) + `on_mold_shutdown` | `before_worker_shutdown` runs in regular workers when they exit. It does **not** run in molds. Use `on_mold_shutdown` for mold-specific teardown (e.g., resource cleanup when the mold is replaced by a newer mold or the cluster stops). |

### Mold-Worker Migration Guide (From Fork-Worker)

1. Move any resource-cleanup logic from your `before_refork` (`on_refork`) hook to `on_mold_promotion`.
2. Remove your `after_refork` hook (molds never resume serving). If it re-establishes connections, move that logic to `before_worker_boot` (`on_worker_boot`) so it runs in each newly-forked worker.
3. Review your `before_worker_shutdown` (`on_worker_shutdown`) hook. Logic related to finishing in-flight requests stays there. Logic related to process teardown that should also apply to molds should be duplicated to `on_mold_shutdown`.
4. Replace `fork_worker` with `mold_worker` in your CLI invocation or config file. Consider adding multiple thresholds with increasing intervals to improve shared-memory efficiency and cache warmth over time (e.g., `mold_worker 1000, 5000, 25000`).
