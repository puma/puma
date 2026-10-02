# frozen_string_literal: true

workers 2
threads 1, 1

bind "tcp://127.0.0.1:#{ENV.fetch('PUMA_BENCH_PORT', 9292)}"

# Each worker gets its index via env var so the rack app can differentiate
before_worker_boot do |index|
  ENV["PUMA_WORKER_INDEX"] = index.to_s
end
