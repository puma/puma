# frozen_string_literal: true

require "puma/control_cli"
require "json"
require "open3"
require_relative "tmp_path"
require_relative "test_puma/puma_socket"

# Only single mode tests go here. Cluster and pumactl tests
# have their own files, use those instead
class TestIntegration < Minitest::Test
  include TmpPath
  include TestPuma
  include TestPuma::PumaSocket

  TOKEN = "xxyyzz"
  RESP_READ_LEN = 65_536
  RESP_READ_TIMEOUT = 10
  RESP_SPLIT = "\r\n\r\n"

  # used in wait_for_server_to_* methods
  LOG_TIMEOUT   = Puma::IS_JRUBY ? 20 : 10
  LOG_WAIT_READ = Puma::IS_JRUBY ? 5 : 2
  LOG_ERROR_SLEEP = 0.2
  LOG_ERROR_QTY   = 5

  # rubyopt requires bundler/setup, so we don't need it here
  BASE = "#{Gem.ruby} -Ilib"

  def setup
    @server = nil
    @server_running = nil # set to true in cli_server, set to false in `stop_server`
    @config_file = nil
    @server_log = +''
    @pid = nil
    @ios_to_close = []
    @bind_path    = tmp_path('.sock')
  end

  def teardown
    if @server_running
      if @server && defined?(@control_port) && Puma.windows?
        cli_pumactl 'stop'
      elsif @server && @pid && !Puma.windows?
        stop_server @pid, signal: :INT
      end
    end

    @ios_to_close&.each do |io|
      begin
        io.close if io.respond_to?(:close) && !io.closed?
      rescue
      ensure
        io = nil
      end
    end

    if @bind_path
      refute File.exist?(@bind_path), "Bind path must be removed after stop"
      File.unlink(@bind_path) rescue nil
    end

    # wait until the end for OS buffering?
    if @server
      begin
        @server.close unless @server.closed?
      rescue
      ensure
        @server = nil

        if @config_file
          File.unlink(@config_file.path) rescue nil
          @config_file = nil
        end
      end
    end
  end

  private

  def silent_and_checked_system_command(*args)
    assert(system(*args, out: File::NULL, err: File::NULL))
  end

  def cli_server(argv,  # rubocop:disable Metrics/ParameterLists
      unix: false,      # uses a UNIXSocket for the server listener when true
      config: nil,      # string to use for config file
      no_bind: nil,     # bind is defined by args passed or config file
      merge_err: false, # merge STDERR into STDOUT
      log: false,       # output server log to console (for debugging)
      no_wait: false,   # don't wait for server to boot
      puma_debug: nil,  # set env['PUMA_DEBUG'] = 'true'
      env: {})          # pass env setting to Puma process in IO.popen

    if config
      @config_file = Tempfile.create(%w(config .rb))
      @config_file.write config
      @config_file.close
      config = "-C #{@config_file.path}"
    end

    puma_path = File.expand_path '../../../bin/puma', __FILE__

    cmd =
      if no_bind
        "#{BASE} #{puma_path} #{config} #{argv}"
      elsif unix
        "#{BASE} #{puma_path} #{config} -b unix://#{@bind_path} #{argv}"
      else
        @tcp_port = UniquePort.call
        @bind_port = @tcp_port
        "#{BASE} #{puma_path} #{config} -b tcp://#{HOST}:#{@tcp_port} #{argv}"
      end

    env['PUMA_DEBUG'] = 'true' if puma_debug

    STDOUT.syswrite "\n#{full_name}\n  #{cmd}\n" if log

    if merge_err
      @server = IO.popen(env, cmd, :err=>[:child, :out])
    else
      @server = IO.popen(env, cmd)
    end
    @server_running = !!@server
    @pid = @server.pid
    wait_for_server_to_boot(log: log) unless no_wait
    @server
  end

  # rescue statements are just in case method is called with a server
  # that is already stopped/killed, especially since Process.wait2 is
  # blocking
  def stop_server(pid = @pid, signal: :TERM)
    begin
      Process.kill signal, pid
      @server_running = nil
    rescue Errno::ESRCH
    end
    begin
      Process.wait2 pid
    rescue Errno::ECHILD
      [nil, nil]
    end
  end

  # Most integration tests do not stop/shutdown the server, which is handled by
  # `teardown` in this file.
  # For tests that do stop/shutdown the server, use this method to check with `wait2`,
  # and also clear variables so `teardown` will not run its code.
  def wait_server(exit_code = 0, pid: @pid)
    return unless pid
    begin
      _, status = Process.wait2 pid
      assert_equal exit_code, status
    rescue Errno::ECHILD # raised on Windows ?
    end
  ensure
    @server&.close unless @server&.closed?
    @server = nil
  end

  def restart_server_and_listen(argv, env: {}, log: false)
    cli_server argv, env: env, log: log
    socket = send_http
    initial_reply = socket.read_body
    restart_server socket, log: log
    [initial_reply, send_http_read_resp_body]
  end

  # reuses an existing connection to make sure that works
  def restart_server(socket, log: false)
    Process.kill :USR2, @pid
    wait_for_server_to_include 'Restarting', log: log
    wait_for_server_to_boot log: log
  end

  # wait for server to say it booted
  # @server and/or @server.gets may be nil on slow CI systems
  def wait_for_server_to_boot(timeout: LOG_TIMEOUT, log: false)
    @puma_pid = wait_for_server_to_match(/(?:Master|      ) PID: (\d+)$/, 1, timeout: timeout, log: log)&.to_i
    @pid = @puma_pid if @pid != @puma_pid
    wait_for_server_to_include 'Ctrl-C', timeout: timeout, log: log
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

    raise Minitest::Assertion,  "@server is not an IO" unless @server.is_a?(IO)
    if Process.clock_gettime(Process::CLOCK_MONOTONIC) > time_timeout
      raise Minitest::Assertion, "Timeout waiting for server to log #{match_obj.inspect}",
        caller(2, 2)
    end

    begin
      if @server.wait_readable(LOG_WAIT_READ) and line = @server&.gets
        @server_log << line
        puts "    #{line}" if log
      end
    rescue StandardError => e
      error_retries += 1
      raise(e, "Waiting for server to log #{match_obj.inspect}", caller(2, 2)) if error_retries == LOG_ERROR_QTY
      sleep LOG_ERROR_SLEEP
      retry
    end
    if Process.clock_gettime(Process::CLOCK_MONOTONIC) > time_timeout
      raise Minitest::Assertion, "Timeout waiting for server to log #{match_obj.inspect}",
        caller(2, 2)
    end
    line
  end

  def connect(path = nil, unix: false)
    s = unix ? UNIXSocket.new(@bind_path) : TCPSocket.new(HOST, @tcp_port)
    @ios_to_close << s
    s << "GET /#{path} HTTP/1.1\r\n\r\n"
    s
  end

  # use only if all socket writes are fast
  # does not wait for a read
  def fast_connect(path = nil, unix: false)
    s = unix ? UNIXSocket.new(@bind_path) : TCPSocket.new(HOST, @tcp_port)
    @ios_to_close << s
    fast_write s, "GET /#{path} HTTP/1.1\r\n\r\n"
    s
  end

  def fast_write(io, str)
    n = 0
    while true
      begin
        n = io.syswrite str
      rescue Errno::EAGAIN, Errno::EWOULDBLOCK => e
        unless io.wait_writable 5
          raise e
        end

        retry
      rescue Errno::EPIPE, SystemCallError, IOError => e
        raise e
      end

      return if n == str.bytesize
      str = str.byteslice(n..-1)
    end
  end

  def read_body(connection, timeout = nil)
    read_response(connection, timeout).last
  end

  def read_response(connection, timeout = nil)
    timeout ||= RESP_READ_TIMEOUT
    content_length = nil
    chunked = nil
    response = +''
    t_st = Process.clock_gettime Process::CLOCK_MONOTONIC
    if connection.to_io.wait_readable timeout
      loop do
        begin
          part = connection.read_nonblock(RESP_READ_LEN, exception: false)
          case part
          when String
            unless content_length || chunked
              chunked ||= part.include? "\r\nTransfer-Encoding: chunked\r\n"
              content_length = (t = part[/^Content-Length: (\d+)/i , 1]) ? t.to_i : nil
            end

            response << part
            hdrs, body = response.split RESP_SPLIT, 2
            unless body.nil?
              # below could be simplified, but allows for debugging...
              ret =
                if content_length
                  body.bytesize == content_length
                elsif chunked
                  body.end_with? "\r\n0\r\n\r\n"
                elsif !hdrs.empty? && !body.empty?
                  true
                else
                  false
                end
              if ret
                return [hdrs, body]
              end
            end
            sleep 0.000_1
          when :wait_readable, :wait_writable # :wait_writable for ssl
            sleep 0.000_2
          when nil
            raise EOFError
          end
          if timeout < Process.clock_gettime(Process::CLOCK_MONOTONIC) - t_st
            raise Timeout::Error, 'Client Read Timeout'
          end
        end
      end
    else
      raise Timeout::Error, 'Client Read Timeout'
    end
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
  def thread_run_refused(unix: false)
    if unix
      DARWIN ? [IOError, Errno::ENOENT, Errno::EPIPE] :
               [IOError, Errno::ENOENT]
    else
      # Errno::ECONNABORTED is thrown intermittently on TCPSocket.new
      DARWIN ? [IOError, Errno::ECONNREFUSED, Errno::EPIPE, Errno::EBADF, EOFError, Errno::ECONNABORTED] :
               [IOError, Errno::ECONNREFUSED, Errno::EPIPE]
    end
  end

  def set_pumactl_args(unix: false)
    if unix
      @control_path = tmp_path('.cntl_sock')
      "--control-url unix://#{@control_path} --control-token #{TOKEN}"
    else
      @control_port = UniquePort.call
      "--control-url tcp://#{HOST}:#{@control_port} --control-token #{TOKEN}"
    end
  end

  def cli_pumactl(argv, unix: false, no_bind: nil)
    arg =
      if no_bind
        argv.split(/ +/)
      elsif unix || @control_path
        %W[-C unix://#{@control_path} -T #{TOKEN} #{argv}]
      else
        %W[-C tcp://#{HOST}:#{@control_port} -T #{TOKEN} #{argv}]
      end

    r, w = IO.pipe
    @ios_to_close << r
    Puma::ControlCLI.new(arg, w, w).run
    w.close
    r
  end

  def cli_pumactl_spawn(argv, unix: false, no_bind: nil)
    arg =
      if no_bind
        argv
      elsif unix || @control_path
        %Q[-C unix://#{@control_path} -T #{TOKEN} #{argv}]
      else
        %Q[-C tcp://#{HOST}:#{@control_port} -T #{TOKEN} #{argv}]
      end

    pumactl_path = File.expand_path '../../../bin/pumactl', __FILE__

    cmd = "#{BASE} #{pumactl_path} #{arg}"

    io = IO.popen(cmd, :err=>[:child, :out])
    @ios_to_close << io
    io
  end

  def get_stats
    read_pipe = cli_pumactl "stats"
    JSON.parse(read_pipe.readlines.last)
  end

  def hot_restart_does_not_drop_connections(num_threads: 1, total_requests: 500)
    skipped = true
    skip_if :jruby, suffix: <<-MSG
 - file descriptors are not preserved on exec on JRuby; connection reset errors are expected during restarts
    MSG
    skip_if :truffleruby, suffix: ' - Undiagnosed failures on TruffleRuby'

    args = "-w #{workers} -t 5:5 -q test/rackup/hello_with_delay.ru"
    if Puma.windows?
      @control_port = UniquePort.call
      cli_server "--control-url tcp://#{HOST}:#{@control_port} --control-token #{TOKEN} #{args}"
    else
      cli_server args
    end

    skipped = false
    replies = Hash.new 0
    refused = thread_run_refused unix: false
    message = 'A' * 16_256  # 2^14 - 128

    mutex = Mutex.new
    restart_count = 0
    client_threads = []

    num_requests = (total_requests/num_threads).to_i

    num_threads.times do |thread|
      client_threads << Thread.new do
        num_requests.times do |req_num|
          begin
            begin
              socket = send_http "POST / HTTP/1.1\r\nContent-Length: #{message.bytesize}\r\n\r\n#{message}"
            rescue => e
              replies[:write_error] += 1
              raise e
            end
            if "Hello World" == socket.read_body
              mutex.synchronize {
                replies[:success] += 1
                replies[:restart] += 1 if restart_count > 0
              }
            else
              mutex.synchronize { replies[:unexpected_response] += 1 }
            end
          rescue Errno::ECONNRESET, Errno::EBADF, Errno::ENOTCONN
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
        # STDOUT.puts "#{thread} #{replies[:success]}"
      end
    end

    run = true

    restart_thread = Thread.new do
      sleep 0.2  # let some connections in before 1st restart
      while run
        if Puma.windows?
          cli_pumactl 'restart'
        else
          Process.kill :USR2, @pid
        end
        sleep 0.5
        # If 'wait_for_server_to_boot' times out, error in thread shuts down CI
        begin
          wait_for_server_to_boot timeout: 5
        rescue Minitest::Assertion # Timeout
          run = false
        end
        restart_count += 1
        sleep(Puma.windows? ? 2.0 : 0.5)
      end
    end

    client_threads.each(&:join)
    run = false
    restart_thread.join
    if Puma.windows?
      cli_pumactl 'stop'
      wait_server
    else
      stop_server
    end
    @server = nil

    msg = ("   %4d unexpected_response\n"   % replies.fetch(:unexpected_response,0)).dup
    msg << "   %4d refused\n"               % replies.fetch(:refused,0)
    msg << "   %4d read timeout\n"          % replies.fetch(:read_timeout,0)
    msg << "   %4d reset\n"                 % replies.fetch(:reset,0)
    msg << "   %4d success\n"               % replies.fetch(:success,0)
    msg << "   %4d success after restart\n" % replies.fetch(:restart,0)
    msg << "   %4d restart count\n"         % restart_count

    refused = replies[:refused]
    reset   = replies[:reset]

    if Puma.windows?
      # 5 is default thread count in Puma?
      reset_max = num_threads * restart_count
      assert_operator reset_max, :>=, reset, "#{msg}Expected reset_max >= reset errors"
      assert_operator 40, :>=,  refused, "#{msg}Too many refused connections"
    else
      assert_equal 0, reset, "#{msg}Expected no reset errors"
      max_refused = (0.001 * replies.fetch(:success,0)).round
      assert_operator max_refused, :>=, refused, "#{msg}Expected no than #{max_refused} refused connections"
    end
    assert_equal 0, replies[:unexpected_response], "#{msg}Unexpected response"
    assert_equal 0, replies[:read_timeout], "#{msg}Expected no read timeouts"

    if Puma.windows?
      assert_equal (num_threads * num_requests) - reset - refused, replies[:success]
    else
      assert_equal (num_threads * num_requests), replies[:success]
    end

  ensure
    return if skipped
    if passed?
      msg = "    #{restart_count} restarts, #{reset} resets, #{refused} refused, #{replies[:restart]} success after restart, #{replies[:write_error]} write error"
      $debugging_info << "#{full_name}\n#{msg}\n"
    else
      client_threads.each { |thr| thr.kill if thr.is_a? Thread }
      $debugging_info << "#{full_name}\n#{msg}\n"
    end
  end
end
