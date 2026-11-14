# Cluster mode

Puma also offers "cluster mode". Cluster mode `fork`s workers from a master process. Each child process still has its own thread pool. You can tune the number of workers with the `-w` (or `--workers`) flag:

```
$ puma -t 8:32 -w 3
```

Or with the `WEB_CONCURRENCY` environment variable:

```
$ WEB_CONCURRENCY=3 puma -t 8:32
```

When using a config file, most applications can simply set `workers :auto` (requires the `concurrent-ruby` gem) to match the number of worker processes to the available processors:

```ruby
# config/puma.rb
workers :auto
```

See [`workers :auto` gotchas](../lib/puma/dsl.rb).

Note that threads are still used in cluster mode, and the `-t` thread flag setting is per worker, so `-w 2 -t 16:16` will spawn 32 threads in total, with 16 in each worker process.

If `workers` is set to `:auto`, or the `WEB_CONCURRENCY` environment variable is set to `"auto"`, and the `concurrent-ruby` gem is available in your application, Puma will set the worker process count to the result of [available processors](https://msp-greg.github.io/concurrent-ruby/Concurrent.html#available_processor_count-class_method).

For an in-depth discussion of the tradeoffs of thread and process count settings, [see our docs](deployment/README.md).

In cluster mode, Puma can "preload" your application. This loads all the application code *prior* to forking. Preloading reduces total memory usage of your application via an operating system feature called [copy-on-write](https://en.wikipedia.org/wiki/Copy-on-write).

If the number of workers is greater than 1 (and `--prune-bundler` has not been specified), preloading will be enabled by default. Otherwise, you can use the `--preload` flag from the command line:

```
$ puma -w 3 --preload
```

Or, if you're using a configuration file, you can use the `preload_app!` method:

```ruby
# config/puma.rb
workers 3
preload_app!
```

Preloading can’t be used with phased restart, since phased restart kills and restarts workers one-by-one, and preloading copies the code of master into the workers.

## Cluster mode hooks

When using clustered mode, Puma's configuration DSL provides `before_fork`, `before_worker_boot`, and `after_worker_shutdown`
hooks to run code when the master process forks, the child workers are booted, and after each child worker exits respectively.

It is recommended to use these hooks with `preload_app!`, otherwise constants loaded by your
application (such as `Rails`) will not be available inside the hooks.

```ruby
# config/puma.rb
before_fork do
  # Add code to run inside the Puma master process before it forks a worker child.
end

before_worker_boot do
  # Add code to run inside the Puma worker process after forking.
end

after_worker_shutdown do |worker_handle|
  # Add code to run inside the Puma master process after a worker exits. `worker.process_status` can be used to get the
  # `Process::Status` of the exited worker.
end
```

In addition, there are `before_refork` and `after_refork` hooks which are used only in [`fork_worker` mode](#fork-worker-cluster-mode-experimental),
when the worker 0 child process forks a grandchild worker:

```ruby
before_refork do
  # Used only when fork_worker mode is enabled. Add code to run inside the Puma worker 0
  # child process before it forks a grandchild worker.
end
```

```ruby
after_refork do
  # Used only when fork_worker mode is enabled. Add code to run inside the Puma worker 0
  # child process after it forks a grandchild worker.
end
```

Importantly, note the following considerations when Ruby forks a child process:

1. File descriptors such as network sockets **are** copied from the parent to the forked
   child process. Dual-use of the same sockets by parent and child will result in I/O conflicts
   such as `SocketError`, `Errno::EPIPE`, and `EOFError`.
2. Background Ruby threads, including threads used by various third-party gems for connection
   monitoring, etc., are **not** copied to the child process. Often this does not cause
   immediate problems until a third-party connection goes down, at which point there will
   be no supervisor to reconnect it.

Therefore, we recommend the following:

1. If possible, do not establish any socket connections (HTTP, database connections, etc.)
   inside Puma's master process when booting.
2. If (1) is not possible, use `before_fork` and `before_refork` to disconnect the parent's socket
   connections when forking, so that they are not accidentally copied to the child process.
3. Use `before_worker_boot` to restart any background threads on the forked child.
4. Use `after_refork` to restart any background threads on the parent.

## Fork-Worker Cluster Mode [Experimental]

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

## Mold-Worker Cluster Mode [Experimental]

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

## Using gRPC with Puma in Clustered Mode

This guide shows how to set up gRPC with Puma in a clustered environment using Puma's hooks to manage gRPC's lifecycle methods during forking.

### The Problem

In a clustered Puma setup, you might encounter the following error when using gRPC:

```
grpc cannot be used between calls to GRPC.prefork and GRPC.postfork_child or GRPC.postfork_parent
```

To work correctly, gRPC needs these methods called at specific points in the process lifecycle:
- `GRPC.prefork`: Called before forking.
- `GRPC.postfork_child`: Called in the child process after forking.
- `GRPC.postfork_parent`: Called in the parent process after forking.

Puma provides hooks such as `before_worker_fork`, `after_worker_fork`, and `before_worker_boot` to execute code during these lifecycle events. Understanding the behavior of these hooks is key to ensuring gRPC operates correctly in a clustered setup.

### The Solution

#### Example Configuration

This configuration integrates gRPC's lifecycle methods in a clustered Puma setup and works whether preloading is enabled or not.

```ruby
# config/puma.rb

is_mac = RUBY_PLATFORM.include?("darwin")

before_worker_fork do |index|
  GRPC.prefork unless is_mac
end

after_worker_fork do |index|
  GRPC.postfork_parent unless is_mac
end

before_worker_boot do
  GRPC.postfork_child unless is_mac
end
```

#### Understanding the Lifecycle and Hooks

Puma's hooks determine when to call gRPC's lifecycle methods. Each hook plays a specific role in managing the lifecycle during forking:

- **`before_worker_fork`**:
  - This hook runs before forking workers and is where you call `GRPC.prefork`.
  - In preloading setups (default in Puma v7), it runs in the **master process** before workers are forked, as the application is preloaded in the master process.
  - Without preloading, it still runs in the **master process** before forking workers, but the application is not preloaded.
  - `GRPC.prefork` is called here to prepare GRPC for the forking process.

- **`after_worker_fork`**:
  - This hook always runs in the **master process** after a worker is forked, regardless of whether preloading is enabled.
  - Call `GRPC.postfork_parent` here to finalize the master process's state after forking.

- **`before_worker_boot`**:
  - This hook always runs in the **worker process** after it is forked, regardless of whether preloading is enabled.
  - Call `GRPC.postfork_child` here to finalize the worker's state.

**Note**: On macOS, these methods are skipped because gRPC does not require them due to differences in how forking works.
