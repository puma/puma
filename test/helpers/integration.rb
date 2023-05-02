# frozen_string_literal: true

require "puma/control_cli"
require "json"
require "io/wait" unless Puma::HAS_NATIVE_IO_WAIT
require_relative 'tmp_path'

class TestIntegration < Minitest::Test
  include TmpPath
  DARWIN = RUBY_PLATFORM.include? 'darwin'
  HOST  = "127.0.0.1"
  TOKEN = "xxyyzz"
  RESP_READ_LEN = 65_536
  RESP_READ_TIMEOUT = 10
  RESP_SPLIT = "\r\n\r\n"

  WAIT_SERVER_TIMEOUT =
    if    ::Puma::IS_MRI  ; 15
    elsif ::Puma::IS_JRUBY; 25
    else                  ; 20 # TruffleRuby
    end

  BASE = defined?(Bundler) ? "bundle exec #{Gem.ruby} -Ilib" :
    "#{Gem.ruby} -Ilib"

  def before_setup
    super
    @server = nil
    @server_err = nil
    @check_server_err = true
    @pid = nil
    @ios_to_close = []
    @bind_path = nil
  end

  def after_teardown
    return if skipped?
    super
    err_out = ''

    if @server_err.is_a?(IO) && @check_server_err
      begin
        if @server_err.wait_readable 0.25
          err_out = @server_err.read_nonblock(2_048, exception: false) || ''
        end
      rescue IOError, Errno::EBADF
      end
    end

    if @server && defined?(@control_tcp_port) && Puma.windows?
      cli_pumactl 'stop'
    elsif @server && @pid && !Puma.windows?
      stop_server @pid, signal: :INT
    end

    @ios_to_close.each do |io|
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

    STDOUT.syswrite("\n-----------------------------------err_out\n#{err_out}\n") unless err_out.empty?
  end

  private

  def silent_and_checked_system_command(*args)
    assert system(*args, out: File::NULL, err: File::NULL)
  end

  def cli_server(argv,    # rubocop:disable Metrics/ParameterLists
      unix: false,        # uses a UNIXSocket for the server listener when true
      config: nil,        # string to use for config file
      no_wait: false,     # don't wait for server to boot
      puma_debug: nil,    # set env['PUMA_DEBUG'] = 'true'
      config_bind: false, # use bind from config
      env: {})            # pass env setting to Puma process in spawn_cmd
    if config
      path = tmp_path_write %w(config .rb), config
      config = "-C #{path}"
    end

    puma_path = File.expand_path '../../../bin/puma', __FILE__
    cmd = +"#{BASE} #{puma_path} #{config}"

    unless config_bind
      if unix
        @bind_path ||= tmp_path '.bind'
        cmd << " -b unix://#{@bind_path}"
      else
        @tcp_port = UniquePort.call
        cmd << " -b tcp://#{HOST}:#{@tcp_port}"
      end
    end
    cmd << " #{argv}" if argv

    env['PUMA_DEBUG'] = 'true' if puma_debug

    @server, @server_err, @pid = spawn_cmd env, cmd
    # =below helpful may be helpful for debugging
    # STDOUT.syswrite "\nPID #{@pid} #{self.class.to_s}##{name}\n"

    @ios_to_close << @server << @server_err

    wait_for_server_to_boot unless no_wait
    @server
  end

  # rescue statements are just in case method is called with a server
  # that is already stopped/killed, especially since Process.wait2 is
  # blocking
  def stop_server(pid = @pid, signal: :TERM)
    @check_server_err = false
    begin
      Process.kill signal, pid
    rescue Errno::ESRCH
    end
    begin
      Process.wait2 pid
    rescue Errno::ECHILD
    end
  end

  def restart_server_and_listen(argv)
    cli_server argv
    connection = connect
    initial_reply = read_body(connection)
    restart_server connection
    [initial_reply, read_body(connect)]
  end

  # reuses an existing connection to make sure that works
  def restart_server(connection)
    Process.kill :USR2, @pid
    connection.write "GET / HTTP/1.1\r\n\r\n" # trigger it to start by sending a new request
    wait_for_server_to_boot
  end

  # wait for server to say it booted
  # @server and/or @server.gets may be nil on slow CI systems
  def wait_for_server_to_boot(no_error: false)
    wait_for_server_to_include 'Ctrl-C'
  rescue => e
    raise e.message unless no_error
  end

  # Returns true if and when server log includes str.
  # Will timeout or raise an error otherwise
  def wait_for_server_to_include(str, io: @server, ret_false_str: nil)
    wait_readable_timeouts = 0
    log_out = +''
    log_out << "Waiting for '#{str}'"
    sleep 0.05 until io.is_a?(IO)
    t_end = Process.clock_gettime(Process::CLOCK_MONOTONIC) + WAIT_SERVER_TIMEOUT
    begin
      loop do
        if io.wait_readable 2
          line = io&.gets
          log_out << line
          return true if line&.include?(str)
        elsif t_end < Process.clock_gettime(Process::CLOCK_MONOTONIC)
          unless wait_readable_timeouts.zero?
            log_out << "#{wait_readable_timeouts} io.wait_readable timeouts, 2 sec each\n"
          end
          STDOUT.syswrite "\n#{log_out}\n"
          raise "Waited too long for server log to include '#{str}'"
        else
          wait_readable_timeouts += 1
        end
      end
    rescue Errno::EBADF, Errno::ECONNREFUSED, Errno::ECONNRESET, IOError => e
      STDOUT.syswrite "\n#{log_out}\n"
      raise "#{e.class} #{e.message}\n  while waiting for server log to include '#{str}'"
    end
  end

  # Returns line if and when server log matches re, unless idx is specified,
  # then returns regex match.
  # Will timeout or raise an error otherwise
  def wait_for_server_to_match(re, idx = nil, io: @server, ret_false_re: nil)
    wait_readable_timeouts = 0
    log_out = +''
    log_out << "Waiting for '#{re.inspect}'"
    sleep 0.05 until io.is_a?(IO)
    t_end = Process.clock_gettime(Process::CLOCK_MONOTONIC) + WAIT_SERVER_TIMEOUT
    begin
      loop do
        if io.wait_readable 2
          line = io&.gets
          log_out << line
          return false if ret_false_re&.match? line
          return (idx ? line[re, idx] : line) if line&.match?(re)
        elsif t_end < Process.clock_gettime(Process::CLOCK_MONOTONIC)
          unless wait_readable_timeouts.zero?
            log_out << "#{wait_readable_timeouts} io.wait_readable timeouts, 2 sec each\n"
          end
          STDOUT.syswrite "\n#{log_out}\n"
          raise "Waited too long for server log to match '#{re.inspect}'"
        else
          wait_readable_timeouts += 1
        end
      end
    rescue Errno::EBADF, Errno::ECONNREFUSED, Errno::ECONNRESET, IOError => e
      STDOUT.syswrite "\n#{log_out}\n"
      raise "#{e.class} #{e.message}\n  while waiting for server log to match '#{re.inspect}'"
    end
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
    read_response(connection, timeout).split(RESP_SPLIT, 2).last
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
                return response
              end
            end
            sleep 0.000_1
          when :wait_readable, :wait_writable # :wait_writable for ssl
            sleep 0.000_2
          when nil
            if response.empty?
              raise EOFError
            else
              return response
            end
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
  def get_worker_pids(phase = 0, size = workers)
    pids = []
    re = /\(PID: (\d+)\) booted in [.0-9]+s, phase: #{phase}/
    while pids.size < size
      if pid = wait_for_server_to_match(re, 1)
        pids << pid
      end
    end
    pids.map(&:to_i)
  end

  # used to define correct 'refused' errors
  def thread_run_refused(unix: false)
    if unix
      DARWIN ? [IOError, Errno::ENOENT, Errno::EPIPE, Errno::ENOTSOCK] :
               [IOError, Errno::ENOENT, Errno::ENOTSOCK]
    else
      # Errno::ECONNABORTED is thrown intermittently on TCPSocket.new
      DARWIN ? [IOError, Errno::ECONNREFUSED, Errno::EPIPE, Errno::EBADF, EOFError, Errno::ECONNABORTED, Errno::ENOTSOCK] :
               [IOError, Errno::ECONNREFUSED, Errno::EPIPE, Errno::EBADF, Errno::ENOTSOCK]
    end
  end

  def set_pumactl_args(unix: false)
    if unix
      @control_path = tmp_path('.cntl_sock')
      "--control-url unix://#{@control_path} --control-token #{TOKEN}"
    else
      @control_tcp_port = UniquePort.call
      "--control-url tcp://#{HOST}:#{@control_tcp_port} --control-token #{TOKEN}"
    end
  end

  def cli_pumactl(argv, unix: false)
    arg =
      if unix
        %W[-C unix://#{@control_path} -T #{TOKEN} #{argv}]
      else
        %W[-C tcp://#{HOST}:#{@control_tcp_port} -T #{TOKEN} #{argv}]
      end
    r, w = IO.pipe
    # Puma::ControlCLI may call exit
    begin
      Puma::ControlCLI.new(arg, w, w).run
    rescue Exception => e
      STDOUT.syswrite "\n--------------------------------------------------- #{e.class}\n"
    end
    w.close
    @ios_to_close << r
    r
  end

  def get_stats
    read_pipe = cli_pumactl "stats"
    JSON.parse(read_pipe.readlines.last)
  end

  def hot_restart_does_not_drop_connections(num_threads: 1, total_requests: 500)
    skip_if :jruby, suffix: "- JRuby file descriptors are not preserved on exec, " \
      "connection reset errors are expected during restarts"

    skip_if :truffleruby, suffix: ' - Undiagnosed failures on TruffleRuby'

    args = "-w#{workers} -t5:5 -q test/rackup/hello_with_delay.ru"
    if Puma.windows?
      cli_server "#{set_pumactl_args} #{args}"
    else
      cli_server args
    end

    replies = Hash.new 0
    refused = thread_run_refused unix: false
    message = 'A' * 16_256  # 2^14 - 128

    mutex = Mutex.new
    restart_count = 0
    client_threads = []

    num_requests = (total_requests/num_threads).to_i

    req_loop = -> () {
      num_requests.times do |req_num|
        begin
          begin
            socket = TCPSocket.new HOST, @tcp_port
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
        rescue Errno::ECONNRESET, Errno::EBADF, Errno::ENOTCONN
          # connection was accepted but then closed
          # client would see an empty response
          # Errno::EBADF Windows may not be able to make a connection
          mutex.synchronize { replies[:reset] += 1 }
        rescue *refused
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
    }

    run = true

    restart_thread = Thread.new do
      sleep 0.2  # let some connections in before 1st restart
      while run
        if Puma.windows?
          cli_pumactl 'restart'
        else
          Process.kill :USR2, @pid
        end
        wait_for_server_to_boot(no_error: true)
        restart_count += 1
        sleep(Puma.windows? ? 2.0 : 0.5)
      end
    end

    if num_threads > 1
      num_threads.times do |thread|
        client_threads << Thread.new do
          req_loop.call
        end
      end
    else
      req_loop.call
    end

    client_threads.each(&:join) if num_threads > 1
    run = false
    restart_thread.join
    if Puma.windows?
      cli_pumactl 'stop'
      Process.wait @pid
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
      reset_max = num_threads * restart_count
      assert_operator reset_max, :>=, reset, "#{msg}Expected reset_max >= reset errors"
      assert_operator 40, :>=,  refused, "#{msg}Too many refused connections"
    else
      max_error = (0.002 * replies.fetch(:success,0) + 0.5).round
      assert_operator max_error, :>=, refused, "#{msg}Expected no more than #{max_error} refused connections"
      assert_operator max_error, :>=, reset  , "#{msg}Expected no more than #{max_error} reset connections"
    end
    assert_equal 0, replies[:unexpected_response], "#{msg}Unexpected response"
    assert_equal 0, replies[:read_timeout], "#{msg}Expected no read timeouts"

    assert_equal (num_threads * num_requests) - reset - refused, replies[:success]

  ensure
    unless @skip
      if passed?
        refused = replies[:refused]
        reset   = replies[:reset]
        msg = "    #{restart_count} restarts, #{reset} resets, #{refused} refused, " \
          "#{replies[:restart]} success after restart, #{replies[:write_error]} write error"
        $debugging_info << "#{full_name}\n#{msg}\n"
      else
        client_threads.each { |thr| thr.kill if thr.is_a? Thread }
        $debugging_info << "#{full_name}\n#{msg}\n"
      end
    end
  end

  def spawn_cmd(env = {}, cmd)
    opts = {}

    out_r, out_w = IO.pipe
    opts[:out] = out_w

    err_r, err_w = IO.pipe
    opts[:err] = err_w

    pid = spawn(env, cmd, opts)
    [out_w, err_w].each(&:close)
    [out_r, err_r, pid]
  end
end
