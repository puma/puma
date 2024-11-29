# frozen_string_literal: true

require_relative 'bench_base'
require_relative 'puma_info'
require 'json'

module TestPuma

  # This file is called from `long_tail_hey.sh`.  It requires `hey`.
  # See https://github.com/rakyll/hey.
  #
  # It starts a `Puma` server, then collects data from one or more runs of hey.
  # It logs the hey data as each hey run is done, then summarizes the data.
  #
  # benchmarks/local/long_tail_hey.sh -t5:5 -R20 -d0.2
  #
  # benchmarks/local/long_tail_hey.sh -w4 -t5:5 -R100 -d0.2
  #
  # See the file 'Testing - benchmark/local files' for sample output and information
  # on arguments for the shell script.
  #
  # Examples:
  #
  # * `benchmarks/local/long_tail_hey.sh -w2 -t5:5 -s tcp6 -Y`<br/>
  #   2 Puma workers, Puma threads 5:5, IPv6 http
  #
  # * `benchmarks/local/response_time_wrk.sh -t6:6 -s tcp -Y -b ac10,50,100`<br/>
  #   Puma single mode (0 workers), Puma threads 6:6, IPv4 http, six wrk runs,
  #   [array, chunk] * [10kb, 50kb, 100kb]
  #
  class LongTailHey < ResponseTimeBase

    HEY = ENV.fetch('HEY', 'hey')

    CONNECTION_MULT = [1.0, 1.5, 2.0, 3.0, 4.0]

    def run
      time_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      super

      @errors = false

      summaries = Hash.new { |h,k| h[k] = {} }

      @stats_data = {}

      @hey_data = {}

      STDOUT.syswrite "\n"

      cpu_qty = ENV['HEY_CPUS']
      hey_cpus = cpu_qty ? "-cpus #{cpu_qty} " : ""

      CONNECTION_MULT.each do |mult|
        workers = @workers || 1
        connections = (mult * @threads * workers).round
        @ka = @no_keep_alive ? "-disable-keepalive" : ""

        hey_cmd = %Q[#{HEY} -c #{format '%3d', connections} -n #{format '%5d', connections * @req_per_connection} #{hey_cpus}#{@ka} #{@wrk_bind_str}/sleep#{@dly_app}]

        @hey_data[connections] = run_hey_parse hey_cmd, mult, log: false

        @puma_info.run 'gc'

        @stats_data[connections] = parse_stats
      end

      run_summaries
    rescue => e
      puts e.class, e.message, e.backtrace
    ensure
      puts ''
      @puma_info.run 'stop'
      sleep 1
      running_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - time_start
      STDOUT.syswrite format("\n%2d:%02d Total Time\n", (running_time/60).to_i, running_time % 60)
    end

    # Prints parsed data of each wrk run. Similar to:
    # ```
    # Type   req/sec    50%     75%     90%     99%    100%  Resp Size
    # ─────────────────────────────────────────────────────────────────    1kB
    # array   13760    0.74    2.51    5.22    7.76   11.18      2797
    # ```
    #
    # @param summaries [Hash]
    #
    def run_summaries
      if @errors
#        puts "\n#{label}   req/sec    50%     75%     90%     99%    100%  Resp Size  Errors"
#        desc_width = 83
      else
        worker_str = @workers.nil? ? '   ' : "-w#{@workers}"
        worker_div = 100/@workers.to_f

        str = "\n\n" \
          "Branch: #{%x[git branch --show-current].strip.ljust 16} " \
          "Puma: #{worker_str.ljust 4} -t#{@threads}:#{@threads}  dly #{@dly_app}"

        str_len = str.length

        str << if @workers.nil? || @workers < 2
          "\n#{@ka.ljust 18}       ─────────────────────────── Latency ───────────────────────────\n" \
          "Mult/Conn     req/sec      10%     25%     50%     75%     90%     95%     99%    100%\n"
        else
          wid_1 = [2, 5, 7, 10, 12, 15, 17]
          ind_1 = wid_1[@workers - 2]

          # workers   3  4   5   6   7   8
          wid_2 = [3, 5, 8, 10, 13, 15, 18]
          wid_3 = [2, 5, 7, 10, 12, 15, 17]
          ind_2 = wid_2[@workers - 2]
          ind_3 = wid_3[@workers - 2]


          "#{' ' * (93 - str_len)}#{'─' * ind_1} Worker Request Info #{'─' * ind_1}\n" \
          "#{@ka.ljust 18   }       ─────────────────────────── Latency ───────────────────────────    Std" \
            "#{' ' * ind_2}% deviation#{' ' * ind_3}Total\n" \
          "Mult/Conn     req/sec      10%     25%     50%     75%     90%     95%     99%    100%      Dev" \
            "#{' ' * ind_2}from #{format '%5.2f', worker_div}%#{' ' * ind_3} Reqs\n"
        end

        STDOUT.syswrite str
      end

      @hey_data.each do |k, data|
        STDOUT.syswrite "#{data[:mult]} #{k.to_s.rjust 3} #{data[:rps].to_s.rjust 12}  "
        data[:latency].each { |pc, time| STDOUT.syswrite "#{time.to_s.rjust 8}" }

        if (@workers || 0)> 1
          # print worker request info from stats
          if stats = @stats_data[k]
            div = k * @req_per_connection/100.to_f
            ttl_req = 0
            req = []
            stats.each do |_,v|
              t = v[:requests]
              ttl_req += t
              req << t/div.to_f
            end
            n = req.length.to_f

            sq_sum = 0
            sum = 0
            req.each do |i|
              sq_sum += i**2
              sum += i
            end
            var = (sq_sum - sum**2/n)/n
            STDOUT.syswrite format('  %7.3f', Math.sqrt(var))

            # req.sort.each { |r| STDOUT.syswrite format(' %5.2f', r) }
            percents = req.sort.map do |r|
              percent = 100 * (r - worker_div)/worker_div
              fmt = percent.between?(-9.9, 9.9) ? ' %4.1f' : ' %4d'
              format fmt, percent
            end.join

            STDOUT.syswrite "  #{percents}  #{format ' %5d', ttl_req}"
          end
          STDOUT.syswrite "\n"
        else
          STDOUT.syswrite "\n"
        end
      end
    end

    def puts(*ary)
      ary.each { |s| STDOUT.syswrite "#{s}\n" }
    end
  end
end
TestPuma::LongTailHey.new.run
