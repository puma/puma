# frozen_string_literal: true

# Reproduction client for keep-alive process affinity issue (puma/puma#3835).
#
# Theory: A proxy/router maintains a pool of keep-alive connections to Puma
# workers. When all pooled connections are busy, the proxy creates a NEW
# connection. The fast worker finishes sooner, so its connections return to
# the idle pool first. While the slow worker is still busy, new connections
# are created and accepted by the idle (fast) worker. Over time the pool
# accumulates more connections to the fast worker.
#
# After priming, when ALL workers do the same amount of work, requests
# still go through the keep-alive pool. The worker with more connections
# receives more requests but can only process one at a time (1 thread),
# so requests queue up -- even while the other worker sits idle.
#
# This script:
#   1. Identifies both workers and establishes one connection to each.
#   2. Keeps the slow worker busy with a 500ms request, then opens extra
#      connections that all go to the idle fast worker -> biased pool.
#   3. Fires concurrent measurement requests over those pooled connections.
#   4. Fires the same measurement with fresh connections (no keep-alive).
#   5. Compares the latency distributions.

require "net/http"
require "optparse"

HOST = "127.0.0.1"
PORT = Integer(ENV.fetch("PUMA_BENCH_PORT", 9292))

options = {
  port: PORT,
  extra_conns: 4,
  rounds: 20,
}

OptionParser.new do |o|
  o.on("--port PORT", Integer)         { |v| options[:port] = v }
  o.on("--extra-conns N", Integer)     { |v| options[:extra_conns] = v }
  o.on("--rounds N", Integer)          { |v| options[:rounds] = v }
end.parse!(ARGV)

port = options[:port]
extra_conns = options[:extra_conns]
rounds = options[:rounds]

def percentile(sorted, pct)
  return sorted.first if sorted.size <= 1
  k = (pct / 100.0) * (sorted.size - 1)
  f = k.floor
  c = k.ceil
  f == c ? sorted[f] : sorted[f] * (c - k) + sorted[c] * (k - f)
end

def timed_get(http, path)
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  resp = http.get(path)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  [elapsed, resp.body]
end

def make_conn(host, port)
  http = Net::HTTP.new(host, port)
  http.open_timeout = 5
  http.read_timeout = 5
  http.start
  http
end

def report(label, latencies, bodies)
  sorted = latencies.sort
  p50  = percentile(sorted, 50) * 1000
  p90  = percentile(sorted, 90) * 1000
  p99  = percentile(sorted, 99) * 1000
  max  = sorted.last * 1000
  mean = (sorted.sum / sorted.size.to_f) * 1000

  dist = Hash.new(0)
  bodies.each { |b| dist[b[/pid=(\d+)/, 1]] += 1 }
  dist_str = dist.sort_by { |_, v| -v }.map { |pid, n| "pid #{pid}: #{n}" }.join(", ")

  puts format(
    "  %-16s n=%-4d  mean=%7.1fms  p50=%7.1fms  p90=%7.1fms  p99=%7.1fms  max=%7.1fms",
    label, sorted.size, mean, p50, p90, p99, max
  )
  puts "  %-16s distribution: %s" % ["", dist_str]
  { p50: p50, p99: p99, mean: mean }
end

# ── Verify server is running ──────────────────────────────────────────────────
begin
  Net::HTTP.start(HOST, port) { |h| h.read_timeout = 5; h.get("/pid") }
rescue => e
  abort "Cannot connect to #{HOST}:#{port}: #{e.message}\nStart puma first."
end

total_conns = 2 + extra_conns

puts "=" * 78
puts "Keep-alive process affinity reproduction (puma/puma#3835)"
puts "=" * 78
puts
puts "Config: #{total_conns} keep-alive connections (2 base + #{extra_conns} extra), #{rounds} measurement rounds"
puts "Server: #{HOST}:#{port} (2 workers, 1 thread each)"
puts

# ── Phase 1: Build the biased connection pool ─────────────────────────────────
#
# Step A: Get one connection to each worker. We hit /pid (instant) in a loop
#         until we've seen two distinct PIDs.
# Step B: Send /prime (500ms) on the slow worker's connection to occupy it.
#         While it's busy, create extra connections -- the idle fast worker
#         accepts them all.
# Result: pool has (1 + extra_conns) connections to the fast worker, 1 to slow.

puts "─" * 78
puts "Phase 1: Building biased connection pool (simulating proxy behavior)"
puts

# Step A: discover both workers
workers = {} # pid -> { conn:, idx: }
attempts = 0
while workers.size < 2 && attempts < 30
  c = make_conn(HOST, port)
  _, body = timed_get(c, "/pid")
  pid = body[/pid=(\d+)/, 1]
  idx = body[/worker=(-?\d+)/, 1].to_i
  if workers.key?(pid)
    c.finish rescue nil
  else
    workers[pid] = { conn: c, idx: idx }
    puts "  Discovered worker #{idx} (pid #{pid})"
  end
  attempts += 1
end

if workers.size < 2
  abort "  ERROR: Could not discover 2 distinct workers after #{attempts} attempts."
end

fast_worker = workers.values.find { |w| w[:idx].even? }
slow_worker = workers.values.find { |w| w[:idx].odd? }

puts
puts "  Fast worker: idx=#{fast_worker[:idx]} (10ms /prime)"
puts "  Slow worker: idx=#{slow_worker[:idx]} (500ms /prime)"
puts

# Step B: keep slow worker busy, then create extra connections
puts "  Occupying slow worker with /prime (500ms)..."
slow_thread = Thread.new { timed_get(slow_worker[:conn], "/prime") }

# Give the slow worker's request a moment to be picked up
sleep 0.05

puts "  Creating #{extra_conns} extra connections while slow worker is busy..."
connections = [fast_worker[:conn], slow_worker[:conn]]
extra_conns.times do
  c = make_conn(HOST, port)
  elapsed, body = timed_get(c, "/prime")
  pid = body[/pid=(\d+)/, 1]
  puts "    -> #{(elapsed * 1000).round(1)}ms  #{body.strip}"
  connections << c
end

slow_elapsed, slow_body = slow_thread.value
puts "  Slow worker finished: #{(slow_elapsed * 1000).round(1)}ms  #{slow_body.strip}"

# Verify pool distribution
pool_dist = Hash.new(0)
connections.each do |c|
  _, body = timed_get(c, "/pid")
  pool_dist[body[/pid=(\d+)/, 1]] += 1
end

puts
puts "  Connection pool: #{connections.size} connections"
pool_dist.sort_by { |_, v| -v }.each do |pid, n|
  bar = "#" * (n * 4)
  puts "    pid #{pid}: #{n} connections #{bar}"
end
puts

# ── Phase 2: Measure with keep-alive (biased pool) ───────────────────────────
puts "─" * 78
puts "Phase 2: KEEP-ALIVE measurement (#{connections.size} concurrent requests x #{rounds} rounds)"
puts

ka_latencies = []
ka_bodies = []

rounds.times do
  threads = connections.map { |http| Thread.new { timed_get(http, "/work") } }
  threads.each do |t|
    elapsed, body = t.value
    ka_latencies << elapsed
    ka_bodies << body
  end
end

ka_stats = report("keep-alive", ka_latencies, ka_bodies)

connections.each { |c| c.finish rescue nil }

puts

# ── Phase 3: Measure without keep-alive (fresh connections) ───────────────────
puts "─" * 78
puts "Phase 3: NO KEEP-ALIVE measurement (#{total_conns} fresh connections x #{rounds} rounds)"
puts

nka_latencies = []
nka_bodies = []

rounds.times do
  threads = Array.new(total_conns) do
    Thread.new do
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      resp = Net::HTTP.get_response(URI("http://#{HOST}:#{port}/work"))
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
      [elapsed, resp.body]
    end
  end
  threads.each do |t|
    elapsed, body = t.value
    nka_latencies << elapsed
    nka_bodies << body
  end
end

nka_stats = report("no-keep-alive", nka_latencies, nka_bodies)

# ── Summary ───────────────────────────────────────────────────────────────────
puts
puts "=" * 78
puts "SUMMARY"
puts "=" * 78
puts format("  Keep-alive:     p50=%7.1fms  p99=%7.1fms  mean=%7.1fms", ka_stats[:p50], ka_stats[:p99], ka_stats[:mean])
puts format("  No keep-alive:  p50=%7.1fms  p99=%7.1fms  mean=%7.1fms", nka_stats[:p50], nka_stats[:p99], nka_stats[:mean])
puts

bias = pool_dist.values.max.to_s + ":" + pool_dist.values.min.to_s

# Use p50 for comparison -- it's robust to the occasional very-bad round
# that pulls the no-keep-alive mean/p99 up.
ka_p50  = ka_stats[:p50]
nka_p50 = nka_stats[:p50]

if ka_p50 > nka_p50 * 1.15
  pct = ((ka_p50 / nka_p50) - 1) * 100
  puts "  REPRODUCED: Keep-alive p50 is %.0f%% worse than no-keep-alive p50." % pct
  puts
  puts "  The keep-alive pool has a #{bias} connection distribution across 2 workers,"
  puts "  each with only 1 thread. Requests to the overloaded worker queue behind"
  puts "  each other while the other worker sits idle."
  puts
  puts "  See: https://github.com/puma/puma/discussions/3835"
else
  puts "  NOT REPRODUCED: Keep-alive p50 is not significantly worse."
  puts "  Pool distribution was #{bias}. Try re-running or increasing --extra-conns."
end
puts
