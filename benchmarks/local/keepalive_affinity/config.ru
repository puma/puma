# frozen_string_literal: true

# Rack app for reproducing keep-alive process affinity issues.
#
# Endpoints:
#   /prime  - Asymmetric: worker 0 is fast (10ms), worker 1 is slow (500ms).
#             This causes keep-alive clients to accumulate connections on the fast worker.
#   /work   - Uniform: all workers sleep the same amount (200ms).
#             With keep-alive affinity, requests pile up on the worker with more connections.
#   /pid    - Returns the worker PID (useful for debugging).

FAST_SLEEP  = 0.01   # 10ms
SLOW_SLEEP  = 0.5    # 500ms
WORK_SLEEP  = 0.2    # 200ms - uniform work

resp_env = { "Content-Type" => "text/plain" }.freeze

# Read at request time (not load time) because preloading runs before
# the before_worker_boot hook sets the env var.
run lambda { |env|
  path = env["REQUEST_PATH"] || env["PATH_INFO"]
  worker_index = ENV.fetch("PUMA_WORKER_INDEX", "-1").to_i

  case path
  when "/prime"
    delay = worker_index.even? ? FAST_SLEEP : SLOW_SLEEP
    sleep delay
    [200, resp_env.dup, ["prime pid=#{Process.pid} worker=#{worker_index} slept=#{delay}\n"]]

  when "/work"
    sleep WORK_SLEEP
    [200, resp_env.dup, ["work pid=#{Process.pid} worker=#{worker_index} slept=#{WORK_SLEEP}\n"]]

  when "/pid"
    [200, resp_env.dup, ["pid=#{Process.pid} worker=#{worker_index}\n"]]

  else
    [200, resp_env.dup, ["ok pid=#{Process.pid}\n"]]
  end
}
