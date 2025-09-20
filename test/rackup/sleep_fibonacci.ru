# frozen_string_literal: true

=begin
This runs loops of fibonacci code to use some CPU resources, then sleeps for the
balance of time that's sent in the request.  The body returned is a text string
that includes the percent of time spent in the fibonacci code.

Call with "GET /sleep<d> HTTP/1.1\r\n\r\n", where <d> is the number of
seconds to sleep, normally a float.

This may fail with an error if the fibonacci code takes longer than the delay
amount.  If so, increase the number in line 19 or lower the number in line 20

Can be tested with curl.
=end

regex_delay = /\A\/sleep(\d+(?:\.\d+)?)/

fibonacci = ->(n) { n <= 1 ? n : fibonacci.call(n - 1) + fibonacci.call(n - 2) }

run lambda { |env|
  delay = (env['REQUEST_PATH'][regex_delay,1] || '0').to_f
  t_st = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  loops = (delay/0.0015).to_i
  loops = 1 if loops.zero?
  loops.times { fibonacci.call 20 }
  t_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  sleep(delay + t_st - t_end)
  percent = 100 * (t_end - t_st)/delay
  [200, {"Content-Type" => "text/plain"}, [format("%6.3f Delay   %4.1f%% CPU   %3d Loops\n", delay, percent, loops)]]
}
