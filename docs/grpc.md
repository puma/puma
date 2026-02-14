# Using gRPC with Puma in Clustered Mode

This guide shows how to set up gRPC with Puma in a clustered environment using Puma's hooks to manage gRPC's lifecycle methods during forking.

## The Problem

In a clustered Puma setup, you might encounter the following error when using gRPC:

```
grpc cannot be used between calls to GRPC.prefork and GRPC.postfork_child or GRPC.postfork_parent
```

To work correctly, gRPC needs these methods called at specific points in the process lifecycle:
- `GRPC.prefork`: Called before forking.
- `GRPC.postfork_child`: Called in the child process after forking.
- `GRPC.postfork_parent`: Called in the parent process after forking.

Puma provides hooks such as `on_worker_fork`, `after_worker_fork`, and `on_worker_boot` to execute code during these lifecycle events. Understanding the behavior of these hooks is key to ensuring gRPC operates correctly in a clustered setup.

## The Solution

### Example Configuration

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

### Understanding the Lifecycle and Hooks

Puma's hooks determine when to call gRPC's lifecycle methods. Each hook plays a specific role in managing the lifecycle during forking:

- **`on_worker_fork`**:
  - This hook runs before forking workers and is where you call `GRPC.prefork`.
  - In preloading setups (default in Puma v7), it runs in the **master process** before workers are forked, as the application is preloaded in the master process.
  - Without preloading, it still runs in the **master process** before forking workers, but the application is not preloaded.
  - `GRPC.prefork` is called here to prepare GRPC for the forking process.

- **`after_worker_fork`**:
  - This hook always runs in the **master process** after a worker is forked, regardless of whether preloading is enabled.
  - Call `GRPC.postfork_parent` here to finalize the master process's state after forking.

- **`on_worker_boot`**:
  - This hook always runs in the **worker process** after it is forked, regardless of whether preloading is enabled.
  - Call `GRPC.postfork_child` here to finalize the worker's state.

**Note**: On macOS, these methods are skipped because gRPC does not require them due to differences in how forking works.
