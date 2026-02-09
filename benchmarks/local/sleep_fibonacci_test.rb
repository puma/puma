# frozen_string_literal: true

=begin
change to benchmarks/local folder

ruby sleep_fibonacci_test.rb s
ruby sleep_fibonacci_test.rb m
ruby sleep_fibonacci_test.rb l
ruby sleep_fibonacci_test.rb a
ruby sleep_fibonacci_test.rb 0.001,0.005,0.01,0.02,0.04
=end

module SleepFibonacciTest

  class << self

    TIME_RE  = / ([\d.]+) Time/
    LOOPS_RE = / (\d+) Loops\n\z/
    CPU_RE   = / ([\d.]+)% CPU/

    FORMAT_DATA = "%5.0f    %6.2f   %6.2f   %6.2f     %3d     %4.1f%%\n"

    LEGEND = " Delay ─── Min ──── Aver ─── Max ─── Loops ─── CPU ─── all times mS ──\n"

    CLK_MONO = Process::CLOCK_MONOTONIC

    def run(blk)
      @app = blk
    end

    def test_single(delay)
      sum_time = 0
      sum_loops = 0
      sum_cpu = 0
      min = 1_000_000
      max = 0
      10.times do
        env = {'REQUEST_PATH' => "/sleep#{delay}"}
        t_st = Process.clock_gettime CLK_MONO
        info = @app.call(env)[2].first
        time = Process.clock_gettime(CLK_MONO) - t_st
        # STDOUT.syswrite "              #{info}"
        sum_loops += info[LOOPS_RE ,1].to_i
        sum_time += time
        sum_cpu += info[CPU_RE ,1].to_f
        min = time if time < min
        max = time if time > max
      end
      STDOUT.syswrite format(FORMAT_DATA,
        1000.0 * delay,
        1000.0 * min,
        100.0  * sum_time,
        1000.0 * max,
        sum_loops/10.0,
        sum_cpu/10.0
        )
    end

    def test
      instance_eval File.read("#{__dir__}/../../test/rackup/sleep_fibonacci.ru")

      # Small   0.001 - 0.009
      # Medium  0.01  - 0.09
      # Large   0.1   - 0.9
      # All
      type = ARGV[0] || 'm' # run all
      if type.match?(/[AaSsMmLl]/)
        STDOUT.syswrite LEGEND
        9.times { |i| test_single(0.001 * (i+1)) } if type.match?(/[SsAa]/)
        STDOUT.syswrite LEGEND if type.match?(/[Aa]/)
        9.times { |i| test_single(0.01  * (i+1)) } if type.match?(/[MmAa]/)
        STDOUT.syswrite LEGEND if type.match?(/[Aa]/)
        9.times { |i| test_single(0.1   * (i+1)) } if type.match?(/[LlAa]/)
      else
        sleep_ary = type.split(',').map(&:to_f)

        sleep_ary.each do |slp|
          env = {'REQUEST_PATH' => "/sleep#{slp}"}
          puts @app.call(env)[2].first
        end
      end
    end
  end
end

SleepFibonacciTest.test
