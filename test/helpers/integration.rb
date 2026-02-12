# frozen_string_literal: true

require "puma/control_cli"
require "json"
require "open3"
require_relative 'tmp_path'

# Only single mode tests go here. Cluster and pumactl tests
# have their own files, use those instead
class TestIntegration < PumaTest
  include TmpPath
  HOST  = "127.0.0.1"
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
    @server_log = +''
    @server_stopped = false
    @config_file = nil

    @pid = nil

    @ios_to_close = Queue.new
    @ios_to_close = []
    @bind_path    = nil
    @bind_port    = nil
    @control_path = nil
    @control_port = nil
  end

  def teardown
    if @server && !@server_stopped
      if @control_port && Puma::IS_WINDOWS
        cli_pumactl 'halt'
      elsif @pid && !Puma::IS_WINDOWS
        stop_server signal: :INT
      elsif Puma::IS_WINDOWS
        flunk 'Windows must use Puma::ControlCLI to shut down!'
      end
    end

    close_ios if @ios_to_close

    # wait until the end for OS buffering?
    if @server
      begin
        @server.close unless @server.closed?
      rescue
      ensure
        @server = nil
      end
    end

    if @bind_path
      refute File.exist?(@bind_path), "Bind path must be removed after stop"
      File.unlink(@bind_path) rescue nil
      @bind_path = nil
    end

    if @control_path
      refute File.exist?(@control_path), "Control path must be removed after stop"
      File.unlink(@control_path) rescue nil
      @control_path = nil
    end

    if @state_path
      File.unlink(@state_path) rescue nil
      @state_path = nil
    end

    if @config_file
      File.unlink(@config_file) rescue nil
      @config_file = nil
    end

    [@state_path, @control_path].each { |p| File.unlink(p) rescue nil }
  end

  private

  def close_ios
    until @ios_to_close.empty?
      io = @ios_to_close.pop
      begin
        if io.respond_to? :sysclose
          io.sync_close = true
          io.sysclose unless io.closed?
        else
          io.close if io.respond_to?(:close) && !io.closed?
          if io.is_a?(File) && (path = io&.path) && File.exist?(path)
            File.unlink path
          end
        end
      rescue Errno::EBADF, Errno::ENOENT, IOError
      ensure
        io = nil
      end
    end
    @ios_to_close = nil
  end

  def bind_path
    @bind_path ||= tmp_path('.sock')
  end

  def bind_port
    @bind_port ||= UniquePort.call
  end

  def control_path
    @control_path ||= tmp_path('.cntl_sock')
  end

  def control_port
    @control_port ||= UniquePort.call
  end

  def silent_and_checked_system_command(*args)
    assert(system(*args, out: File::NULL, err: File::NULL))
  end

  def with_unbundled_env
    bundler_ver = Gem::Version.new(Bundler::VERSION)
    if bundler_ver < Gem::Version.new('2.1.0')
      Bundler.with_clean_env { yield }
    else
      Bundler.with_unbundled_env { yield }
    end
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
      @config_file.syswrite config
      # not supported on some OS's, all GitHub Actions OS's support it
      @config_file.fsync rescue nil
      @config_file.close
      config = "-C #{@config_file.path}"
    end

    puma_path = File.expand_path '../../../bin/puma', __FILE__

    cmd =
      if no_bind
        "#{BASE} #{puma_path} #{config} #{argv}"
      elsif unix
        "#{BASE} #{puma_path} #{config} -b unix://#{bind_path} #{argv}"
      else
        "#{BASE} #{puma_path} #{config} -b tcp://#{HOST}:#{bind_port} #{argv}"
      end

    env['PUMA_DEBUG'] = 'true' if puma_debug

    STDOUT.syswrite "\n#{full_name}\n  #{cmd}\n" if log

    if merge_err
      @server = IO.popen(env, cmd, :err=>[:child, :out])
    else
      @server = IO.popen(env, cmd)
    end
    @pid = @server.pid
    wait_for_server_to_boot(log: log) unless no_wait
    @server
  end

  # rescue statements are just in case method is called with a server
  # that is already stopped/killed, especially since Process.wait2 is
  # blocking
  def stop_server(pid = @pid, signal: :TERM)
    ret = nil
    begin
      Process.kill signal, pid
    rescue Errno::ESRCH
    end
    begin
      ret = Process.wait2 pid
    rescue Errno::ECHILD
    end
    @server_stopped = true
    ret
  end

  # Most integration tests do not stop/shutdown the server, which is handled by
  # `teardown` in this file.
  # For tests that do stop/shutdown the server, use this method to check with `wait2`,
  # and also clear variables so `teardown` will not run its code.
  def wait_server(exit_code = 0, pid: @pid)
    return unless pid
    begin
      _, status = Process.wait2 pid
      status = status.exitstatus % 128 if ::Puma::IS_JRUBY
      assert_equal exit_code, status
    rescue Errno::ECHILD # raised on Windows ?
    end
  ensure
    @server.close unless @server.closed?
    @server = nil
  end

  def restart_server_and_listen(argv, env: {}, log: false)
    cli_server argv, env: env, log: log
    connection = connect
    initial_reply = read_body(connection)
    restart_server connection, log: log
    [initial_reply, read_body(connect)]
  end

  # reuses an existing connection to make sure that works
  def restart_server(connection, log: false)
    Process.kill :USR2, @pid
    wait_for_server_to_include 'Restarting', log: log
    connection.write "GET / HTTP/1.1\r\n\r\n" # trigger it to start by sending a new request
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

    sleep 0.05 until @server.is_a?(IO) || Process.clock_gettime(Process::CLOCK_MONOTONIC) > time_timeout

    raise Minitest::Assertion,  "@server is not an IO" unless @server.is_a?(IO)
    if Process.clock_gettime(Process::CLOCK_MONOTONIC) > time_timeout
      raise Minitest::Assertion, "Timeout waiting for server to log #{match_obj.inspect}"
    end

    begin
      if @server.wait_readable(LOG_WAIT_READ) and line = @server&.gets
        @server_log << line
        puts "    #{line}" if log
      end
    rescue StandardError => e
      error_retries += 1
      raise(Minitest::Assertion,  "Waiting for server to log #{match_obj.inspect} raised #{e.class}") if error_retries == LOG_ERROR_QTY
      sleep LOG_ERROR_SLEEP
      retry
    end
    if Process.clock_gettime(Process::CLOCK_MONOTONIC) > time_timeout
      raise Minitest::Assertion, "Timeout waiting for server to log #{match_obj.inspect}"
    end
    line
  end

  def open_client_socket(unix: false, timeout: 3)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    retries = 0
    begin
      unix ? UNIXSocket.new(@bind_path) : TCPSocket.new(HOST, bind_port)
    rescue Errno::EADDRNOTAVAIL => e
      raise e if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      retries += 1
      sleep 0.01 * retries.clamp(0, 10)
      retry
    end
  end

  def connect(path = nil, unix: false)
    s = open_client_socket(unix: unix)
    @ios_to_close << s
    s << "GET /#{path} HTTP/1.1\r\n\r\n"
    s
  end

  # use only if all socket writes are fast
  # does not wait for a read
  def fast_connect(path = nil, unix: false)
    s = open_client_socket(unix: unix)
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
      DARWIN ? [IOError, Errno::ENOENT, Errno::EPIPE, Errno::EBADF] :
               [IOError, Errno::ENOENT]
    else
      # Errno::ECONNABORTED is thrown intermittently on TCPSocket.new
      # Errno::ECONNABORTED is thrown by Windows on read or write
      DARWIN ? [IOError, Errno::ECONNREFUSED, Errno::EADDRNOTAVAIL, Errno::EPIPE, Errno::EBADF, EOFError, Errno::ECONNABORTED] :
               [IOError, Errno::ECONNREFUSED, Errno::EADDRNOTAVAIL, Errno::EPIPE, Errno::ECONNABORTED]
    end
  end

  def set_pumactl_args(unix: false)
    if unix
      "--control-url unix://#{control_path} --control-token #{TOKEN}"
    else
      "--control-url tcp://#{HOST}:#{control_port} --control-token #{TOKEN}"
    end
  end

  def set_pumactl_config(unix: false)
    if unix
      @control_path = tmp_path('.cntl_sock')
      "activate_control_app 'unix://#{control_path}', { auth_token: '#{TOKEN}' }"
    else
      @control_port = UniquePort.call
      "activate_control_app 'tcp://#{HOST}:#{control_port}', { auth_token: '#{TOKEN}' }"
    end
  end

  def cli_pumactl(argv, unix: false, no_bind: nil)
    arg =
      if no_bind
        argv.split(/ +/)
      elsif @control_path && !@control_port
        %W[-C unix://#{@control_path} -T #{TOKEN} #{argv}]
      elsif @control_port && !@control_path
        %W[-C tcp://#{HOST}:#{@control_port} -T #{TOKEN} #{argv}]
      else
        flunk 'Both @control_path and @control_port esist?'
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
      elsif @control_path && !@control_port
        %Q[-C unix://#{@control_path} -T #{TOKEN} #{argv}]
      elsif @control_port && !@control_path
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
    read_pipe.wait_readable 2
    # `split("\n", 2).last` removes "Command stats sent success" line
    JSON.parse read_pipe.read.split("\n", 2).last
  end

  def restart_does_not_drop_connections(
      num_threads: 1,
      total_requests: 500,
      config: nil,
      unix: nil,
      signal: nil,
      log: nil
    )
    skipped = true
    skip_if :jruby, suffix: ' - file descriptors are not preserved on exec on JRuby; ' \
      'connection reset errors are expected during restarts'
    skip_if :truffleruby, suffix: ' - Undiagnosed failures on TruffleRuby'
    skipped = nil

    clustered = (workers || 0) >= 2

    args = "-w #{workers} -t 5:5 -q test/rackup/hello_with_delay.ru"
    if Puma.windows?
      cli_server "#{set_pumactl_args} #{args}", unix: unix, config: config, log: log
    else
      cli_server args, unix: unix, config: config, log: log
    end

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
              socket = open_client_socket(unix: unix)
              fast_write socket, "POST / HTTP/1.1\r\nContent-Length: #{message.bytesize}\r\n\r\n#{message}"
            rescue => e
              replies[:write_error] += 1
              raise e
            end
            body = read_body(socket, 10)
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
        # STDOUT.puts "#{thread} #{replies[:success]}"
      end
    end

    run = true

    restart_thread = Thread.new do
      # Wait for some connections before first restart
      sleep 0.2
      while run
        if Puma.windows?
          cli_pumactl 'restart'
        else
          Process.kill signal, @pid
        end
        if signal == :USR2
          # If 'wait_for_server_to_boot' times out, error in thread shuts down CI
          begin
            wait_for_server_to_boot timeout: 5
          rescue Minitest::Assertion # Timeout
            run = false
          end
        end
        restart_count += 1

        if Puma.windows?
          sleep 2.0
        elsif clustered
          phase = signal == :USR2 ? 0 : restart_count
          # If 'get_worker_pids phase' times out, error in thread shuts down CI
          begin
            get_worker_pids phase, log: log
            # Wait with an exponential backoff before signaling next restart
            sleep 0.15 * restart_count
          rescue Minitest::Assertion # Timeout
            run = false
          rescue Errno::EBADF # bad restart?
            run = false
          end
        else
          sleep 0.1
        end
      end
    end

    # cycle thru threads rather than one at a time
    until client_threads.empty?
      client_threads.each_with_index do |t, i|
        client_threads[i] = nil if t.join(1)
      end
      client_threads.compact!
    end

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
    msg << "   %4d write_errors\n"          % replies.fetch(:write_error,0)
    msg << "   %4d success\n"               % replies.fetch(:success,0)
    msg << "   %4d success after restart\n" % replies.fetch(:restart,0)
    msg << "   %4d restart count\n"         % restart_count

    actual_requests = num_threads * num_requests
    allowed_errors = (actual_requests * 0.002).round

    refused = replies[:refused]
    reset   = replies[:reset]

    assert_operator restart_count, :>=, 2, msg

    if Puma.windows?
      assert_equal actual_requests - reset - refused, replies[:success]
    else
      assert_operator replies[:success], :>=,  actual_requests - allowed_errors, msg
    end

  ensure
    unless skipped
      if passed?
        msg = "    #{restart_count} restarts, #{reset} resets, #{refused} refused, #{replies[:restart]} success after restart, #{replies[:write_error]} write error"
        $debugging_info << "#{full_name}\n#{msg}\n"
      else
        client_threads.each { |thr| thr.kill if thr.is_a? Thread }
        $debugging_info << "#{full_name}\n#{msg}\n"
      end
    end
  end
end
