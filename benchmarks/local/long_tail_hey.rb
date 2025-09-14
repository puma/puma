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
  # benchmarks/local/long_tail_hey.sh -t5:5 -R20 -d0.2  -C ./test/config/fork_worker.rb
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

    CONNECTION_MULT = [6.0, 4.0, 3.0, 2.0, 1.5, 1.0, 0.5]
    CONNECTION_REQ = []

    def run
      time_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      super

      @errors = false

      summaries = Hash.new { |h,k| h[k] = {} }

      @stats_data = {}
      @hey_data   = {}

      STDOUT.syswrite "\n"

      cpu_qty = ENV['HEY_CPUS']
      hey_cpus = cpu_qty ? "-cpus #{cpu_qty} " : ""

      @ka = @no_keep_alive ? "-disable-keepalive" : ""

      CONNECTION_MULT.each do |mult|
        workers = @workers || 1
        connections = (mult * @threads * workers).round

        CONNECTION_REQ << connections

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

    def run_summaries
      STDOUT.syswrite "\n\n"
      worker_str = @workers.nil? ? '   ' : "-w#{@workers}"
      worker_div = 100/@workers.to_f

      # Below are lines used in data logging
      git_ref = %x[git branch --show-current].strip
      git_ref = %x[git log -1 --format=format:%H][0, 12] if git_ref.empty?
      @desc_line = "Branch: #{git_ref.ljust 16} " \
          "Puma: #{worker_str.ljust 4} -t#{@threads}:#{@threads}  dly #{@dly_app}"
      @hey_info_line = "Mult/Conn  requests"
      @hey_run_data = []

      @hey_data.each do |k, data|
        @hey_run_data[k] = "#{data[:mult]} #{k.to_s.rjust 3}"
      end

      STDOUT.syswrite summary_hey_latency
      STDOUT.syswrite summary_puma_stats
    end

    def summary_hey_latency
      str = @desc_line.dup
      str_len = str.length

      str << "\n#{@ka.ljust 30}  ───────────────────── Hey Latency ───────────────────── Long Tail\n" \
        "#{@hey_info_line}   rps %     10%    25%    50%    75%    90%    95%    99%    100%   100% / 10%\n"

      max_rps = @threads * (@workers || 1)/(100.0 * @dly_app)

      @hey_data.each do |k, data|
        str << format("#{@hey_run_data[k]}   %6d    %6.1f   ", data[:requests], data[:rps].to_f/max_rps)
        mult = data[:mult].to_f
        mult = 1.0 if mult < 1.0
        div = @dly_app * mult
        data[:latency].each { |pc, time| str << format('%6.2f ', time/div) }
          str << format('%9.2f', data[:latency][100]/data[:latency][10])
        str << "\n"
      end
      str << "\n"
    end

    def summary_puma_stats
      str = @desc_line.dup.sub 'Branch: ', ''
      str_len = str.length
      if (@workers || 0) > 1
        # used for 'Worker Request Info' centering
        # worker 2  3  4  5   6   7   8
        wid_1 = [2, 3, 5, 8, 11, 14, 17]
        ind_1 = wid_1[@workers - 2]

        # used for '% deviation' centering
        # worker 2  3   4   5   6   7   8
        wid_2 = [4, 7, 10, 13, 16, 19, 22]
        ind_2 = wid_2[@workers - 2]

        spaces = str_len >= 57 ? ' ' : ' ' * (57 - str_len)
        str << "#{spaces}#{'─' * ind_1} Worker Request Info #{'─' * ind_1}\n"

        str << "#{@ka.ljust 23           }  ── Reactor ──   ── Backlog ──" \
          "    Std #{' ' * ind_2}% deviation\n"

        str << "#{@hey_info_line.ljust 23}   Min     Max     Min     Max " \
          "    Dev #{' ' * ind_2}from #{format '%5.2f', 100/@workers.to_f }%\n"

        CONNECTION_REQ.each do |k|
          backlog_max = []
          reactor_max = []
          requests = []
          hsh = @stats_data[k]

          hsh.each do |k, v|
            backlog_max << v[:backlog_max]
            reactor_max << v[:reactor_max]
            requests << v[:requests]
          end

          str << format("#{@hey_run_data[k]}   %6d       %4d   %5d   %5d   %5d",
            requests.sum, reactor_max.min, reactor_max.max, backlog_max.min, backlog_max.max)

          # convert requests array into sorted percent array
          div = k * @req_per_connection/@workers.to_f
          percents = requests.sort.map { |r| percent = 100.0 * (r - div)/div }

          # std dev calc
          n = requests.length.to_f
          sq_sum = 0
          sum = 0
          percents.each do |i|
            sq_sum += i**2
            sum += i
          end
          var = (sq_sum - sum**2/n)/n

          percents_str = percents.map { |r| r.abs >= 100.0 ? format(' %5.0f', r) : format(' %5.1f', r) }.join

          str << format("   %7.2f  #{percents_str}\n", Math.sqrt(var))
        end
      else
        str << "\n#{@ka.ljust 23           }  ── Reactor ──   ── Backlog ──\n"
        str <<   "#{@hey_info_line.ljust 23}     Min/Max         Min/Max\n"

        one_worker = @workers == 1
        CONNECTION_REQ.each do |k|
          hsh = one_worker ? @stats_data[k].values[0] : @stats_data[k]
          str << format("#{@hey_run_data[k]}   %6d            %3d             %3d\n", hsh[:requests], hsh[:reactor_max], hsh[:backlog_max])
        end
      end
      str << "\n\n"
    end

    def puts(*ary)
      ary.each { |s| STDOUT.syswrite "#{s}\n" }
    end
  end
end
TestPuma::LongTailHey.new.run
