# frozen_string_literal: true

require_relative 'bench_base'
require_relative 'puma_info'

module TestPuma

  # This file is called from `response_time_wrk.sh`.  It requires `wrk`.
  # We suggest using https://github.com/ioquatix/wrk
  #
  # It starts a `Puma` server, then collects data from one or more runs of wrk.
  # It logs the wrk data as each wrk runs is done, then summarizes
  # the data in two tables.
  #
  # The default runs a matrix of the following, and takes a bit over 5 minutes,
  # with 28 (4x7) wrk runs:
  #
  # bodies - array, chunk, string, io<br/>
  #
  # sizes - 1k, 10k, 100k, 256k, 512k, 1024k, 2048k
  #
  # See the file 'Testing - benchmark/local files' for sample output and information
  # on arguments for the shell script.
  #
  # Examples:
  #
  # * `benchmarks/local/response_time_wrk.sh -w2 -t5:5 -s tcp6 -Y`<br/>
  #   2 Puma workers, Puma threads 5:5, IPv6 http, 28 wrk runs with matrix above
  #
  # * `benchmarks/local/response_time_wrk.sh -t6:6 -s tcp -Y -b ac10,50,100`<br/>
  #   Puma single mode (0 workers), Puma threads 6:6, IPv4 http, six wrk runs,
  #   [array, chunk] * [10kb, 50kb, 100kb]
  #
  class ResponseTimeWrk < ResponseTimeBase

    WRK = ENV.fetch('WRK', 'wrk')

    def run
      time_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      super
      # default values
      @duration ||= 10
      max_threads = (@threads[/\d+\z/] || 5).to_i
      @stream_threads ||= (0.8 * (@workers || 1) * max_threads).to_i
      connections = @stream_threads * (@wrk_connections || 2)

      warm_up

      @max_100_time = 0
      @max_050_time = 0
      @errors = false

      summaries = Hash.new { |h,k| h[k] = {} }

      @single_size = @body_sizes.length == 1
      @single_type = @body_types.length == 1

      @body_sizes.each do |size|
        @body_types.each do |pre, desc|
          header = @single_size ? "-H '#{HDR_BODY_CONF}#{pre}#{size}'" :
            "-H '#{HDR_BODY_CONF}#{pre}#{size}'".ljust(21)

          # warmup?
          if pre == :i
            wrk_cmd = %Q[#{WRK} -t#{@stream_threads} -c#{connections} -d1s --latency #{header} #{@wrk_bind_str}]
            %x[#{wrk_cmd}]
          end

          wrk_cmd = %Q[#{WRK} -t#{@stream_threads} -c#{connections} -d#{@duration}s --latency #{header} #{@wrk_bind_str}]
          hsh = run_wrk_parse wrk_cmd

          @errors ||= hsh.key? :errors

          times = hsh[:times_summary]
          @max_100_time = times[1.0] if times[1.0] > @max_100_time
          @max_050_time = times[0.5] if times[0.5] > @max_050_time
          summaries[size][desc] = hsh
        end
        sleep 0.5
        @puma_info.run 'gc'
        sleep 2.0
      end

      run_summaries summaries

      if @single_size || @single_type
        puts ''
      else
        overall_summary(summaries) unless @single_size || @single_type
      end

      puts "wrk -t#{@stream_threads} -c#{connections} -d#{@duration}s"

      env_log

    rescue => e
      puts e.class, e.message, e.backtrace
    ensure
      puts ''
      @puma_info.run 'stop'
      sleep 2
      running_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - time_start
      puts format("\n%2d:%d Total Time", (running_time/60).to_i, running_time % 60)
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
    def run_summaries(summaries)
      digits = [4 - Math.log10(@max_100_time).to_i, 3].min

      fmt_vals = +'%-6s %6d'
      fmt_vals << (digits < 0 ? "  %6d" : "  %6.#{digits}f")*5
      fmt_vals << '  %8d'

      label = @single_type ? 'Size' : 'Type'

      if @errors
        puts "\n#{label}   req/sec    50%     75%     90%     99%    100%  Resp Size  Errors"
        desc_width = 83
      else
        puts "\n#{label}   req/sec    50%     75%     90%     99%    100%  Resp Size"
        desc_width = 65
      end

      puts format("#{'─' * desc_width} %s", @body_types[0][1]) if @single_type

      @body_sizes.each do |size|
        puts format("#{'─' * desc_width}%5dkB", size) unless @single_type
        @body_types.each do |_, t_desc|
          hsh = summaries[size][t_desc]
          times = hsh[:times_summary].values
          desc = @single_type ? size : t_desc
#          puts format(fmt_vals, desc, hsh[:rps], *times, hsh[:read]/hsh[:requests])
          puts format(fmt_vals, desc, hsh[:rps], *times, hsh[:resp_size])
        end
      end

    end

    # Checks if any body files need to be created, reads all the body files,
    # then runs a quick 'wrk warmup' command for each body type
    #
    def warm_up
      puts "\nwarm-up"
      if @body_types.map(&:first).include? :i
        TestPuma.create_io_files @body_sizes

        # get size files cached
        if @body_types.include? :i
          2.times do
            @body_sizes.each do |size|
              fn = format "#{Dir.tmpdir}/.puma_response_body_io/body_io_%04d.txt", size
              t = File.read fn, mode: 'rb'
            end
          end
        end
      end

      size = @body_sizes.length == 1 ? @body_sizes.first : 10

      @body_types.each do |pre, _|
        header = "-H '#{HDR_BODY_CONF}#{pre}#{size}'".ljust(21)
        warm_up_cmd = %Q[#{WRK} -t2 -c4 -d1s --latency #{header} #{@wrk_bind_str}]
        run_wrk_parse warm_up_cmd
      end
      puts ''
    end

    # Experimental - try to see how busy a CI system is.
    def ci_test_rps
      host = ENV['HOST']
      port = ENV['PORT'].to_i

      str = 'a' * 65_500

      server = TCPServer.new host, port

      svr_th = Thread.new do
        loop do
          begin
            Thread.new(server.accept) do |client|
              client.sysread 65_536
              client.syswrite str
              client.close
            end
          rescue => e
            break
          end
        end
      end

      threads = []

      t_st = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      100.times do
        threads << Thread.new do
          100.times {
            s = TCPSocket.new host, port
            s.syswrite str
            s.sysread 65_536
            s = nil
          }
        end
      end

      threads.each(&:join)
      loops_time = (1_000*(Process.clock_gettime(Process::CLOCK_MONOTONIC) - t_st)).to_i

      threads.clear
      threads = nil

      server.close
      svr_th.join

      req_limit =
        if    loops_time > 3_050 then 13_000
        elsif loops_time > 2_900 then 13_500
        elsif loops_time > 2_500 then 14_000
        elsif loops_time > 2_200 then 18_000
        elsif loops_time > 2_100 then 19_000
        elsif loops_time > 1_900 then 20_000
        elsif loops_time > 1_800 then 21_000
        elsif loops_time > 1_600 then 22_500
        else                          23_000
        end
        [req_limit, loops_time]
    end

    def puts(*ary)
      ary.each { |s| STDOUT.syswrite "#{s}\n" }
    end
  end
end
TestPuma::ResponseTimeWrk.new.run
