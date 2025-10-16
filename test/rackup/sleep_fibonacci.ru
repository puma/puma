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

loop_sleep = 0.0001
mod = 2

clk_mono = Process::CLOCK_MONOTONIC

resp_env = {"Content-Type" => "text/plain"}.freeze

fibonacci = ->(n) { n <= 1 ? n : fibonacci.call(n - 1) + fibonacci.call(n - 2) }

app_lambda = ->(env) {
  t_st = Process.clock_gettime(clk_mono)
  delay = (env['REQUEST_PATH'][regex_delay,1] || '0').to_f

  cpu_ttl_time = 0.7 * delay

  loops_sleep = cpu_ttl_time/100.0

  fib_num =
    if    delay < 0.0033
      mod = 4; 16
    elsif delay < 0.01
      mod = 4; 17
    elsif delay < 0.033
      mod = 5; 18
    elsif delay < 0.1
      mod = 5; 20
    elsif delay < 0.33
      mod = 6; 22
    else
      mod = 6; 24
    end

  fib_num -= 3 unless RUBY_ENGINE == 'ruby'

  cpu_time = 0
  loops = 0

  while true
    loop_st = Process.clock_gettime(clk_mono)
    fibonacci.call fib_num
    cpu_time += Process.clock_gettime(clk_mono) - loop_st
    loops += 1
    break if cpu_time > cpu_ttl_time
    sleep loop_sleep if loops % mod == 1
  end
  t_end = Process.clock_gettime(clk_mono)
  if (sleep_left = delay + t_st - t_end - 0.00007) > 0
    sleep sleep_left
  #else
  #  STDOUT.syswrite format("%9.4f  dly %5.3f\n", sleep_left, delay)
  end
  percent_cpu = 100 * cpu_time/delay
  [200, resp_env.dup, [format("%6.4f Delay   %7.5f Time   %4.1f%% CPU   %3d Loops\n",
    delay, Process.clock_gettime(clk_mono) - t_st, percent_cpu, loops
  )]]
}

run app_lambda
