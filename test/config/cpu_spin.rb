# call with "GET /cpu/<d> HTTP/1.1\r\n\r\n",
# where <d> is the number of iterations

require 'benchmark'

# configure `wait_for_less_busy_workers` based on ENV, default `true`
wait_for_less_busy_worker ENV.fetch('WAIT_FOR_LESS_BUSY_WORKERS', '0.005').to_f

app do |env|
  iterations = (env['REQUEST_PATH'][/\/cpu\/(\d.*)/,1] || '1000').to_i

  duration = Benchmark.measure do
    iterations.times { rand }
  end

  [200, {"Content-Type" => "text/plain"}, ["Run for #{duration.total} #{Process.pid}"]]
end
