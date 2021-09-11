# frozen_string_literal: true

require_relative 'bench_base'
require_relative 'puma_info'

module TestPuma

  # This file is meant to be run with `bench_overload_wrk.sh`.  It only works
  # with workers, and it uses smem and @ioquatix's fork of wrk, available at:
  # https://github.com/ioquatix/wrk
  #
  # It starts a Puma server, then runs 5 sets of wrk, with varying threads and
  # connections.  The first set has the thread count equal to total Puma thread
  # count, then four more are run with increasing thread count, ending with three
  # times the intial value.  After each run, Puma stats and smem info are retrieved.
  # Information is logged to the console, summarized, and also returned as a Ruby
  # object, so it may be used for CI.
  #
  # Puma stats includes the request count per worker.  The output shows a metric
  # called 'spread'.  If ary is the array of worker request counts -
  # spread = 100 * (ary.max - ary.min)/ary.average
  #
  # `bench_overload_wrk.sh` arguments
  #
  # Puma Server
  # ```
  # -R rackup file, defaults to ci_string.ru
  # -s socket type, tcp or ssl, no unix with wrk
  # -t same as Puma --thread
  # -w same as Puma --worker
  # -C same as Puma --config
  # The following only apply when using ci_string.ru, ci_array.ru, or ci_chunked.ru
  # -b body size in kB, defaults to 10
  # -d app delay in seconds, defaults to 0
  # ```
  # wrk cmd
  # ```
  # -c wrk connection count per thread, defaults to 10
  # -T wrk time/duration, defaults to 15
  # ```
  #
  # Examples
  #
  # runs wrk with 5 connections per thread and a response body size of 1kB, and a
  # wrk duration of 10 sec.
  # ```
  # benchmarks/local/bench_overload_wrk.sh -c5 -s tcp -w4 -t5:5 -b1 -T10
  # ```
  # runs wrk with 5 connections per thread and use hello.ru, show object info after.
  # ```
  # benchmarks/local/bench_overload_wrk.sh -c5 -s tcp -w4 -t5:5 -C test/config/worker_object_info.rb -R test/rackup/hello.ru
  # ```
  #
  class BenchOverloadWrk < BenchBase

    # delay between wrk finishing and running stats
    DELAY_STATS = 5

    # thread multipliers used for wrk jobs, geometric sequence 1 to 3
    MULTS = [
      1,
      1.316074013,
      1.732050808,
      2.279507057,
      3
    ].freeze

    def run
      @wrk_time ||= 15
      wrk_connections_per_thread = @clients_per_thread > 0 ? @clients_per_thread : 10

      if ENV['CI_TEST_KB']
        puts '', "Reponse body size #{ENV['CI_TEST_KB']} kB, ENV['CI_TEST_KB']"
      end

      @puma_info = PumaInfo.new ['-S', @state_file]

      # main data hash
      @info = []

      # summary hash
      @summary = {}

      @pids = {}
      @pids[@puma_info.master_pid] = 'master'
      @worker_req_ttl = Hash.new 0
      client_dly = 0.000_01

      threads = @threads * @workers
      temp = MULTS.map { |m| (m * threads).round }
      ttl_connections = threads * @clients_per_thread
      loops_clients = temp.map { |m| [m, (ttl_connections/m.to_f).round] }

      temp.each do |t|
        @info << {
          threads: t,
          connections: t * wrk_connections_per_thread,
          smem: nil,
          stats: nil,
          wrk: nil
        }
      end
      @info.unshift({
        threads: @info[0][:threads],
        connections: @info[0][:threads],
        smem: nil,
        stats: nil,
        wrk: nil
      })

      @errors = false

      puts "\n─────────────────────────────────────────────────────────── WRK Overload Stats - app delay #{format '%5.3f s', (@dly_app || 0)}"

      puts '##[group]wrk run data', '' if IS_GHA

      warm_up

      @info[1..-1].each do |info|

        threads, connections = info[:threads], info[:connections]

        header = @dly_app ? "-H 'Dly: #{@dly_app}' " : ""

        wrk_cmd = %Q[wrk #{header}-t#{threads} -c#{connections} -d#{@wrk_time}s --latency #{@wrk_bind_str}]

        hsh = run_wrk_parse wrk_cmd

        info[:wrk] = hsh

        info[:av_resp_size] = (hsh[:read]/hsh[:requests]).round

        @errors = hsh.key? :errors

        sleep DELAY_STATS

        stats = parse_stats
        info[:stats] = stats
        stats_reqs = stats.map { |k, h| h[:requests] }
        hsh[:req_spread] = 100 * (stats_reqs.max - stats_reqs.min) * stats_reqs.length.to_f/stats_reqs.sum
        hsh[:stats_req_ttl] = stats_reqs.sum

        info[:smem] = parse_smem
        run_summary info
      end

      puts '::[endgroup]' if IS_GHA

      overall_summary
      leak_calc
      puts RUBY_DESCRIPTION, ''
      # puts ''; pp @info; puts ''
      sleep 1
      @puma_info.run 'stop'
      sleep 3

      if ENV['GITHUB_ACTIONS']
        limits = {}
        limits[:rps], loops_time = ci_test_rps

        exit_code = 0
        if @summary[:rps] < limits[:rps]
          puts "loops_time #{loops_time}   #{@summary[:rps]} rps is less than #{limits[:rps]}"
          exit_code += 1
        else
          puts "loops_time #{loops_time}   #{@summary[:rps]} rps is acceptable..."
        end
        exit exit_code
      end
    end

    def warm_up
      puts 'warm-up'
      hdr = @dly_app ? "-H 'Dly: #{@dly_app}' " : ""
      wu_loops = @info[0][:threads]
      wu_conns = @info[0][:connections]
      warm_up_cmd = %Q[wrk #{hdr}-t#{wu_loops} -c#{wu_conns} -d2s --latency #{@wrk_bind_str}]

      @info[0][:wrk] = run_wrk_parse warm_up_cmd

      sleep DELAY_STATS
      @info[0][:stats] = parse_stats
      @info[0][:smem] = parse_smem
      run_summary @info[0]
      puts ''
    end

    def run_summary(info)
      str = "#{info[:wrk][:rps].to_s.rjust(info[:wrk][:requests].to_s.length)} req/sec"
      fmt = '%6s %7s %7s %7s  %-12s  %7s'
      puts format(fmt, 'PID', 'RSS', 'PSS', 'USS', 'Desc', "Requests     #{str}")
      info[:smem].each do |k,v|
        reqs = info[:stats][k] ? info[:stats][k][:requests].to_s : ''
        puts format(fmt, *v.values, k, reqs)
      end
      puts ''
    end

    def overall_summary
      puts " WRK and 'Puma stats' Information".rjust(86, '═'), ''

      time_max = 0

      @info[1..-1].each { |info| time_max = (info[:wrk][:times].values.push time_max).max }

      digits = 3 - Math.log10(time_max).to_i
      fmt_vals = '%3d %5d  %7d'.dup
      @info[1][:wrk][:times].length.times { fmt_vals << "  %5.#{digits}f" }
      fmt_vals << '  %5.2f %8d  %8d %5d'

      header_base = '────────wrk────────  ─Request─time─distribution─(ms)─  Worker─requests'

      reqs_puma = 0
      reqs_wrk  = 0
      summary_rps = 0

      if @errors
        fmt_vals << '   %s'
        puts "#{header_base}  ─────────wrk─requests─────────"
        puts " -t    -c   req/sec   50%    75%    90%    99%   100%  spread   total     total   bad         errors"
      else
        puts "#{header_base}  ─wrk─requests─"
        puts " -t    -c   req/sec   50%    75%    90%    99%   100%  spread   total     total   bad"
      end

      @info[1..-1].each do |info|
        wrk = info[:wrk]
        reqs_puma += wrk[:stats_req_ttl]
        reqs_wrk  += wrk[:requests]
        if @errors
          puts format(fmt_vals, info[:threads], info[:connections], wrk[:rps], *wrk[:times].values,
            wrk[:req_spread], wrk[:stats_req_ttl], wrk[:requests], wrk[:stats_req_ttl] - wrk[:requests], wrk[:errors] || '')
        else
          puts format(fmt_vals, info[:threads], info[:connections], wrk[:rps], *wrk[:times].values,
            wrk[:req_spread], wrk[:stats_req_ttl], wrk[:requests], wrk[:stats_req_ttl] - wrk[:requests])
        end
        summary_rps += wrk[:rps] * wrk[:requests]
      end
      if @errors
        puts '', 'errors - c: connection, w: write, r: read, t: timeout'
      end
      @summary[:rps] = (summary_rps/reqs_wrk.to_f).to_i
      puts format("#{' ' * 12}%6d#{' ' * 36}Totals %8d  %8d", @summary[:rps], reqs_puma, reqs_wrk)
      puts '═'*86, ''
    end

    def leak_calc
      workers = @pids.values.reject { |v| v == 'master'}.sort
      len = @info.length - 1

      info_loop = @info[1..-1]

      # mem = [:pss, :rss, :uss]
      mem = [:uss]

      all_resp_size =  info_loop.sum { |h| h[:wrk][:read] } / info_loop.sum { |h| h[:wrk][:requests] }

      fmt = '%-15s%-3s'.dup
      fmt << ' %6d' * len

      width = 18 + 7 * (len+1)

      puts ' Memory Change per Request'.rjust(width, '═')
      puts format    fmt      , 'WRK Threads'    , '' , *info_loop.map { |h| h[:threads]      }
      puts format "#{fmt} %6s", '    Connections', '' , *info_loop.map { |h| h[:connections]  }, 'All'
      puts format "#{fmt} %6d", '    Av Resp Siz', 'e', *info_loop.map { |h| h[:av_resp_size] }, all_resp_size.round
      puts '═' * width

      fmt << '  %5d'

      ttl_leaks = {}
      mem.each { |type| ttl_leaks[type] = Array.new len, 0 }

      ttl_mem = Hash.new Array.new(len, 0)
      ttl_req = Hash.new Array.new(len, 0)

      summary_rps = 0

      workers.each do |w|
        desc = w
        mem.each do |type|
          worker_ttl_req = 0
          leaks = []
          info_loop.each_with_index do |hsh, i|
            smem_last = @info[i][:smem]
            smem, stats = hsh[:smem], hsh[:stats]
            requests = stats[w][:requests]
            ttl_req[type][i] += requests
            worker_ttl_req   += requests
            mem_increase = smem[w][type] - smem_last[w][type]
            ttl_mem[type][i] += mem_increase
            leaks << 1000 * mem_increase/requests
          end
          # total for worker/mem (far right column)
          leaks << 1000 * (@info[-1][:smem][w][type] - @info[0][:smem][w][type])/worker_ttl_req
          puts format fmt, desc, type.to_s.upcase, *leaks
          desc = ''
        end # mem
        puts '─'*width if mem.length > 1
      end # workers

      # Bottom Total Line
      desc = 'All'
      mem.each do |type|
        (0...len).each { |i| ttl_leaks[type][i] = 1000 * ttl_mem[type][i] / ttl_req[type][i] }
        overall = 1000 * ttl_mem[type].sum / ttl_req[type].sum.to_f
        puts format fmt, desc, type.to_s.upcase, *ttl_leaks[type], overall
        desc = ''
      end
      puts '═'*width, ''
    end

    # Try to see how busy a CI system is...
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
TestPuma::BenchOverloadWrk.new.run
