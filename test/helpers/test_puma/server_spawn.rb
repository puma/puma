# frozen_string_literal: true

require "puma/control_cli"
require "json"
require_relative "server_base"

module TestPuma

  # Creates a server by spawning a sub-process and running `bin/puma`.  These
  # should be used for testing of startup, restarts, and shutdown.  They are also
  # isolated from the test environment.  Becuase they spawn a sub-process, they
  # are much slower than in-process servers created with `TestPuma::ServerInProcess`.
  #
  class ServerSpawn < ServerBase

    # used in wait_for_server_to_* methods
    LOG_TIMEOUT   = Puma::IS_JRUBY ? 20 : 10
    LOG_WAIT_READ = Puma::IS_JRUBY ? 5 : 2
    LOG_ERROR_SLEEP = 0.2
    LOG_ERROR_QTY   = 5

    BASE = Puma::IS_WINDOWS ? Gem.ruby : ""

    DFLT_RUBYOPT = ENV['RUBYOPT']

    def before_setup
      super
      @server_err = nil
      @server_log = +''
      @pid = nil
      @spawn_pid = nil
      @cli_pumactl_spawn_pids = []
    end

    def after_teardown
      if @server
        if @control_port && Puma::IS_WINDOWS
          begin
            cli_pumactl 'stop'
          rescue SystemExit
            TestPuma::DEBUGGING_INFO << "ControlCLI system exit #{full_name}\n"
          end
        elsif @pid && !Puma::IS_WINDOWS
          stop_server signal: :INT
        end
      end

      if @spawn_pid && @spawn_pid != @pid
        stop_server @spawn_pid, signal: :INT
      end

      unless @cli_pumactl_spawn_pids.empty?
        @cli_pumactl_spawn_pids.each { |pid| kill_and_wait pid, signal: :INT }
      end

      if @bind_path
        refute File.exist?(@bind_path), "Bind path must be removed after stop"
        File.unlink(@bind_path) rescue nil
      end
      super
    end

    def server_spawn(argv = nil, # rubocop:disable Metrics/ParameterLists
        config: nil,       # string to use for config file
        no_bind: nil,      # if true, binds are defined config file
        log: nil,          # output server log to console (for debugging)
        no_wait: false,    # don't wait for server to boot
        puma_debug: nil,   # set env['PUMA_DEBUG'] = 'true'
        env: {})           # pass env setting to spawned Puma process

      if config
        if no_bind
          config_contents = @bind_type == :ssl ? config :
            "bind '#{bind_uri_str}'\n#{config}"
          if @control_type
            config_contents = "#{control_config_str}\n#{config_contents}"
          end
          config_args = "-C #{config_path config_contents}"
        else
          config_args = "-C #{config_path config}"
        end
      else
        config_args = nil
      end

      puma_path = File.expand_path '../../../bin/puma', __dir__

      cmd =
        if no_bind
          "#{BASE} #{puma_path} #{config_args} #{argv}"
        elsif @control_type
          "#{BASE} #{puma_path} #{config_args} #{set_pumactl_args} -b '#{bind_uri_str}' #{argv}"
        else
          "#{BASE} #{puma_path} #{config_args} -b '#{bind_uri_str}' #{argv}"
        end

      env['PUMA_DEBUG'] = 'true' if puma_debug
      env['RUBYOPT'] = DFLT_RUBYOPT unless ENV['RUBYOPT']

      STDOUT.syswrite "\n——— #{full_name}\n    #{cmd}\n" if log

      @server, @server_err, @spawn_pid = spawn_cmd env, cmd.strip

      wait_for_server_to_include('Ctrl-C', log: log) unless no_wait
      @pid = @server_log[/(?:Master|      ) PID: (\d+)$/, 1]&.to_i || @spawn_pid
      TestPuma::DEBUGGING_PIDS[@pid] = full_name
      TestPuma::DEBUGGING_PIDS[@spawn_pid] = "spawn #{full_name}" if @spawn_pid != @pid
      @server
    end

    # rescue statements are just in case method is called with a server
    # that is already stopped/killed, especially since Process.wait2 is
    # blocking
    def stop_server(pid = @pid, signal: :TERM,  timeout: 10)
      ary = kill_and_wait pid, signal: signal

      if pid == @pid && @spawn_pid != @pid && ary.nil?
        ary = wait2_timeout @spawn_pid,  timeout: timeout
      end

      if pid == @pid
        @server = nil
        @spawn_pid = nil if @spawn_pid == @pid
        @pid = nil
      end
      ary
    end

    def silent_and_checked_system_command(*args)
      assert(system(*args, out: File::NULL, err: File::NULL))
    end

    def restart_server_and_listen(argv, log: false)
      server_spawn argv
      socket = send_http
      initial_reply = socket.read_body
      restart_server socket, log: log
      # Ruby 2.6 and later all read the below socket,
      # Ruby 2.5 intermittently throws Errno::ECONNRESET or EOFError
      socket.read_body unless RUBY_VERSION < '2.6'

      # above socket may be answered by original server
      # below socket answered by restarted server
      [initial_reply, send_http_read_resp_body]
    end

    # reuses an existing connection to make sure that works
    def restart_server(socket, log: false)
      Process.kill :USR2, @pid
      socket << GET_11
      wait_for_server_to_include 'Ctrl-C', log: log
    end

    # Returns true if and when server log includes str.  Will timeout otherwise.
    def wait_for_server_to_include(str, timeout: LOG_TIMEOUT, log: false)
      time_timeout = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      line = ''

      puts "\n——— #{full_name} waiting for '#{str}'" if log
      line = server_gets(str, time_timeout, log: log) until line&.include?(str)
      true
    end

    # Returns line if and when server log matches re, unless idx is specified,
    # then returns regex match.  Will timeout otherwise.
    def wait_for_server_to_match(re, idx = nil, timeout: LOG_TIMEOUT, log: false)
      time_timeout = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      line = ''

      puts "\n——— #{full_name} waiting for '#{re.inspect}'" if log
      line = server_gets(re, time_timeout, log: log) until line&.match?(re)
      idx ? line[re, idx] : line
    end

    def server_gets(match_obj, time_timeout, log: false)
      error_retries = 0
      line = ''

      sleep 0.05 unless @server.is_a?(IO) or Process.clock_gettime(Process::CLOCK_MONOTONIC) > time_timeout

      unless @server.is_a? IO
        raise RuntimeError,  "@server is not an IO"
      end
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > time_timeout
        raise Timeout::Error, "Timeout waiting for server to log #{match_obj.inspect}"
      end

      begin
        if @server.wait_readable(LOG_WAIT_READ) and line = @server&.gets
          @server_log << line
          puts "    #{line}" if log
        end
      rescue StandardError => e
        error_retries += 1
        raise(e, "Waiting for server to log #{match_obj.inspect}") if error_retries == LOG_ERROR_QTY
        sleep LOG_ERROR_SLEEP
        retry
      end
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > time_timeout
        raise Timeout::Error, "Timeout waiting for server to log #{match_obj.inspect}"
      end
      line
    end

    # gets worker pids from @server output
    def get_worker_pids(phase = 0, size = workers, log: false)
      pids = []
      re = /PID: (\d+)\) booted in [.0-9]+s, phase: #{phase}/
      while pids.size < size
        if pid = wait_for_server_to_match(re, 1, log: log)
          pids << pid
        end
      end
      pids.map(&:to_i)
    end

    # used to define correct 'refused' errors
    def thread_run_refused
      DARWIN ? [EOFError, IOError, SystemCallError] : [IOError, SystemCallError]
    end

    def cli_pumactl(argv, no_bind: nil)
      arg =
        if no_bind
          argv.split(/ +/)
        elsif @state_path && !argv.include?(@state_path)
          %W[-S #{@state_path} #{argv}]
        else
          %W[-C #{control_uri_str} -T #{TOKEN} #{argv}]
        end

      r, w = IO.pipe
      @ios_to_close << r
      Puma::ControlCLI.new(arg, w, w).run
      w.close
      r
    end

    def cli_pumactl_spawn(argv, no_bind: nil)
      arg =
        if no_bind
          argv
        elsif @state_path && !argv.include?(@state_path)
          %W[-S #{@state_path} #{argv}]
        else
          %W[-C #{control_uri_str} -T #{TOKEN} #{argv}]
        end

      pumactl_path = File.expand_path '../../../bin/pumactl', __dir__

      cmd = "#{BASE} #{pumactl_path} #{arg}"

      io, _, pid = spawn_cmd cmd
      @cli_pumactl_spawn_pids << pid
      TestPuma::DEBUGGING_PIDS[pid] = "pumactl #{full_name}"
      @ios_to_close << io
      io
    end

    def get_stats
      read_pipe = cli_pumactl "stats"
      JSON.parse(read_pipe.readlines.last)
    end

    def spawn_cmd(env = {}, cmd)
      opts = {}

      out_r, out_w = IO.pipe
      opts[:out] = out_w

      err_r, err_w = IO.pipe
      opts[:err] = err_w

      pid = spawn(env, cmd, opts)
      [out_w, err_w].each(&:close)
      @ios_to_close << out_r << err_r
      [out_r, err_r, pid]
    end

    def hot_restart_does_not_drop_connections(num_threads: 1, total_requests: 500)
      skipped = true
      skip_if :jruby, suffix: <<~MSG
        - file descriptors are not preserved on exec on JRuby; connection reset errors are expected during restarts
      MSG
      skip_if :truffleruby, suffix: ' - Undiagnosed failures on TruffleRuby'
      skipped = false

      args = "-w#{workers} -t 5:5 -q test/rackup/hello_with_delay.ru"
      set_control_type :tcp if Puma::IS_WINDOWS
      server_spawn args

      skipped = false
      replies = Hash.new 0
      refused = thread_run_refused
      message = 'A' * 16_256  # 2^14 - 128
      request = "POST / HTTP/1.1\r\nContent-Length: #{message.bytesize}\r\n\r\n#{message}"

      mutex = Mutex.new
      restart_count = 0
      client_threads = []

      num_requests = (total_requests/num_threads).to_i

      request_loop = ->() do
        num_requests.times do |req_num|
          begin
            begin
              socket = send_http request
            rescue => e
              replies[:write_error] += 1
              raise e
            end
            body = socket.read_body
            if body == "Hello World"
              mutex.synchronize {
                replies[:success] += 1
                replies[:restart] += 1 if restart_count > 0
              }
            else
              mutex.synchronize { replies[:unexpected_response] += 1 }
            end
          rescue Errno::ECONNRESET, Errno::EBADF, Errno::ENOTCONN, Errno::ENOTSOCK
            # connection was accepted but then closed
            # client would see an empty response
            # Errno::EBADF Windows may not be able to make a connection
            mutex.synchronize { replies[:reset] += 1 }
          rescue *refused, IOError
            # IOError intermittently thrown by Ubuntu, add to allow retry
            mutex.synchronize { replies[:refused] += 1 }
          rescue ::Timeout::Error
            mutex.synchronize { replies[:read_timeout] += 1 }
          ensure
            if socket.is_a?(IO) && !socket.closed?
              begin
                socket.close
              rescue Errno::EBADF
              end
            end
          end
        end
      end

      run = true

      restart_thread = Thread.new do
        sleep 0.05  # let some connections in before 1st restart
        while run do
          begin
            if Puma::IS_WINDOWS
              cli_pumactl 'restart'
            else
              Process.kill :USR2, @pid
            end
            wait_for_server_to_include 'Ctrl-C'
            restart_count += 1
            sleep(Puma::IS_WINDOWS ? 1.0 : 0.2)
          rescue Errno::EBADF, Timeout::Error
            break
          end
        end
      end

      if num_threads > 1
        num_threads.times do |thread|
          client_threads << Thread.new do
            begin
              request_loop.call
            rescue StandardError
            end
          end
        end
        client_threads.each do |th|
          begin
            th&.join
          rescue StandardError
          end
        end
      else
        request_loop.call
      end

      run = false
      restart_thread.join
      if Puma::IS_WINDOWS
        cli_pumactl 'stop'
        Process.wait @spawn_pid
      else
        stop_server
      end
      @server = nil

      msg = ("   %4d write error\n"           % replies.fetch(:write_error,0)).dup
      msg << "   %4d unexpected_response\n"   % replies.fetch(:unexpected_response,0)
      msg << "   %4d refused\n"               % replies.fetch(:refused,0)
      msg << "   %4d read timeout\n"          % replies.fetch(:read_timeout,0)
      msg << "   %4d reset\n"                 % replies.fetch(:reset,0)
      msg << "   %4d success\n"               % replies.fetch(:success,0)
      msg << "   %4d success after restart\n" % replies.fetch(:restart,0)
      msg << "   %4d restart count\n"         % restart_count

      refused = replies[:refused]
      reset   = replies[:reset]

      # assert_operator - 1st parameter is logged as expected

      if Puma::IS_WINDOWS
        # 5 is default thread count in Puma?
        max_reset = num_threads * restart_count
        assert_operator max_reset,     :>=, reset  ,  "#{msg}Expected no more than #{max_reset} reset connections"
        assert_operator        50,     :>=, refused,  "#{msg}Expected no more than 40 refused connections"
      else
        max_refused = [0.001 * num_threads * num_requests, 1].max.round.to_i
        assert_operator restart_count, :>=, reset  ,  "#{msg}Expected no more that #{restart_count} reset connections"
        assert_operator max_refused  , :>=, refused,  "#{msg}Expected no more than #{max_refused} refused connections"
      end
      assert_equal 0, replies[:unexpected_response], "#{msg}Unexpected response"
      assert_equal 0, replies[:read_timeout]       , "#{msg}Expected no read timeouts"

      expected = 0.7 * (num_threads * num_requests - reset - refused)

      assert_operator expected, :<=, replies[:restart], "#{msg}Expected more than #{expected} connections after restart"
    ensure
      unless skipped
        if passed?
          msg = "    #{restart_count} restarts, #{reset} resets, #{refused} refused," \
            "#{replies[:write_error]} write error, #{replies[:restart]}/#{replies[:success]} success restart/total"
          TestPuma::DEBUGGING_INFO << "#{full_name}\n#{msg}\n"
        else
          client_threads.each { |thr| thr.kill if thr.is_a? Thread }
          TestPuma::DEBUGGING_INFO << "#{full_name}\n#{msg}\n"
        end
      end
    end
  end
end
