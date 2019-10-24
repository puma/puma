# frozen_string_literal: true

require "puma/control_cli"

# TestIntegration is used with tests that start Puma and then control it, either
# via signals or sockets.  Since control via signals requires a separate process,
# the tests need to create a Puma instance separate from the test process.
# Since the code paths for control via signals vs sockets is somewhat different,
# these tests often test both, althought the 'socket control' tests really don't
# require a separate process.
#
# The main method is #setup_puma, which specifies the bindings and control type.
# Most of the helper methods use variables defined by #setup_puma.
# #setup_puma also allows similar tests to be created where one test uses a
# signal to control Puma, while the companion test uses a tcp or unix socket to
# do the same.
#
# The following methods make use of variables set in #setup_puma:
# * #cli_server - starts an instance of Puma via IO.popen
# * #connect - specify a GET request path, returns the response
# * #run_pumactl - sends a command via Puma::ControlCLI
#
# All methods keep track of opened IO's, and they will be closed in `teardown`.
#
class TestIntegration < Minitest::Test
  include WaitForServerLogs

  DARWIN = !!RUBY_PLATFORM[/darwin/]

  HOST  = '127.0.0.1'
  TOKEN = 'xxyyzz'
  WORKERS = 2

  BASE = defined?(Bundler) ? "bundle exec #{Gem.ruby} -Ilib" :
    "#{Gem.ruby} -Ilib"

  def setup
    @ios_to_close = []

    # below defined so we don't have to check defined? before use
    @pid  = nil
    @bind = nil
    @ctrl = nil
    @server = nil
    @path_bind = nil
    @path_ctrl = nil
    # restarts change the pid of the server due to Kernel.exec
    @path_pid = nil
  end

  def teardown
    return if skipped?

    sgnl = windows? ? :KILL : :INT
    begin
      Process.kill sgnl, @pid
    rescue Errno::ESRCH, Errno::EINVAL
    end if @pid

    begin
      Process.wait @pid
    rescue Errno::ECHILD
    end if @pid

    @ios_to_close.each do |io|
      io.close if io.is_a?(IO) && !io.closed?
      io = nil
    end

    if @path_bind
      refute File.exist?(@path_bind), "Bind path must be removed after stop"
      File.unlink(@path_bind) rescue nil
    end

    if @path_ctrl
      refute File.exist?(@path_ctrl), "Ctrl path must be removed after stop"
      File.unlink(@path_ctrl) rescue nil
    end

    File.unlink(@path_pid) rescue nil

    # wait until the end for OS buffering?
    if defined?(@server) && @server
      @server.close unless @server.closed?
      @server = nil
    end
  end

  private

  # Main method to setup Puma configuration.  Loads the following variables,
  # depending on the parameters. All path variables are based on the test class
  # and method name with specific extension.
  #
  # * Path Variables
  #   * +@path_bind+ - unix binding - +.bind+ extension
  #   * +@path_ctrl+ - unix control - +.ctrl+ extension
  #   * +@path_pid+  - control pid file - +.pid+ extension
  #   * +@path_state+ - control state file - +.state+ extension
  #
  # * TCP Port Variables
  #   * +@port_bind+ - binding
  #   * +@port_ctrl+ - control url
  #
  # @param bind: [:Symbol] The protocol used for the binding.  Either :tcp or :unix
  # @param ctrl: [:Symbol] Sets some of the parameters passed to a Puma::ControlCLI
  # instance. One of the following: :pid, :pidfile, :tcp, :tcp_state, :unix,
  # :unix_state. The 'state' ctrl options use the prefix for the protocol, along
  # with a state file.
  #
  def setup_puma(bind: :nil, ctrl: :nil)

    if bind.nil? && ctrl.nil?
      raise ArgumentError, "both bind and ctrl cannot be nil"
    end

    if (bind == :unix) || [:unix, :unix_state].include?(ctrl)
      skip UNIX_SKT_MSG unless HAS_UNIX
    end

    if windows? && [:pid, :pidfile].include?(ctrl)
      skip "Puma::ControlCLI doesn't support pid/signal on Windows"
    end

    case bind
    when :tcp
      @port_bind = UniquePort.call
    when :unix
      @path_bind = "tmp/#{full_file_name}.bind"
    when nil
    else
      raise ArgumentError, "cli_server invalid bind: value - #{ctrl}"
    end
    @bind = bind

    case ctrl
    when :pid
    when :pidfile
    when :tcp
      @port_ctrl  = UniquePort.call
    when :tcp_state
      @port_ctrl  = UniquePort.call
      @path_state = "tmp/#{full_file_name}.state"
    when :unix
      @path_ctrl  = "tmp/#{full_file_name}.ctrl"
    when :unix_state
      @path_ctrl  = "tmp/#{full_file_name}.ctrl"
      @path_state = "tmp/#{full_file_name}.state"
    when nil
    else
      raise ArgumentError, "cli_server invalid ctrl: value - #{ctrl}"
    end
    @ctrl = ctrl
  end

  # Starts an instance of Puma in a sepate process via IO.popen.
  # @param args [:String] Additional options not set via #setup_puma.
  # @return [IO] IO object return from IO.popen.
  def cli_server(args)
    cmd = "#{BASE} bin/puma -b ".dup

    case @bind
    when :tcp
      cmd << "tcp://#{HOST}:#{@port_bind} "
    when :unix
      cmd << "unix://#{@path_bind} "
    else
      raise ArgumentError, "cli_server invalid @bind value - #{@bind}"
    end

    case @ctrl
    when :pid, :pidfile
    when :tcp
      cmd << "--control-url tcp://#{HOST}:#{@port_ctrl} --control-token #{TOKEN} "
    when :tcp_state
      cmd << "--control-url tcp://#{HOST}:#{@port_ctrl} --control-token #{TOKEN} "
      cmd << "-S #{@path_state} "
    when :unix
      cmd << "--control-url unix://#{@path_ctrl} --control-token #{TOKEN} "
    when :unix_state
      cmd << "--control-url unix://#{@path_ctrl} --control-token #{TOKEN} "
      cmd << "-S #{@path_state} "
    else
      raise ArgumentError, "cli_server invalid @ctrl value - #{@ctrl}"
    end

    # alwys write pid file
    @path_pid = "tmp/#{full_file_name}.pid"
    cmd << "--pidfile #{@path_pid} "

    cmd << args
    @server = IO.popen(cmd.split, err: :out)
    @ios_to_close << @server
    assert_io 'Ctrl-C'
    @pid = File.read(@path_pid, mode: 'rb').strip.to_i

    @server
  end

  # Creates a Puma::ControlCLI object and runs it.
  # @param cmd_str [:String] The command to run.
  # @return [IO, IO] the out and err IO objects passed to Puma::ControlCLI.new
  #
  def run_pumactl(cmd_str)
    cmd = case @ctrl
      when :pid
        @pid = File.read(@path_pid, mode: 'rb').strip.to_i
        "-p #{@pid} "
      when :pidfile    then "-P #{@path_pid} "
      when :tcp        then "-C tcp://#{HOST}:#{@port_ctrl} -T #{TOKEN} "
      when :tcp_state  then "-S #{@path_state} "
      when :unix       then "-C unix://#{@path_ctrl} -T #{TOKEN} "
      when :unix_state then "-S #{@path_state} "
      else
        raise ArgumentError, "run_pumactl invalid @ctrl value - #{@ctrl}"
      end.dup
    cmd << cmd_str

    out_r, out_w = IO.pipe
    err_r, err_w = IO.pipe

    Puma::ControlCLI.new(cmd.split, out_w, err_w).run

    out_w.close      ; err_w.close
    out = out_r.read ; err = err_r.read
    out_r.close      ; err_r.close
    [out, err]
  end

  # Issues a stop command to the Puma server, and waits for 'Goodbye'.  Use with
  # `Single` Puma instances.
  #
  def stop_server_goodbye
    run_pumactl 'stop'
    assert_io 'Goodbye'
  end

  # Issues a stop command to the Puma server, and waits via `Process.wait`. Use
  # with `Cluster` Puma instances.
  #
  def stop_server_wait
    run_pumactl 'stop'
    begin
      Process.wait @pid
    rescue Errno::ECHILD
    end
  end

  # Start a server with provided arguements, connects, restarts, connects again,
  # and returns the two connection replies.
  # @param args [:String] Additional options not set via #setup_puma.
  # @return [String, String] Response bodies from the connection before and after
  # the restart.
  # @note 'restart', not 'phased-restart'
  def restart_server_and_listen(args)
    cli_server args

    pre = read_body

    restart_server

    [pre, read_body]
  end

  # Restarts a server (not phased-restart), and waits for 'Ctrl-C'.  Since
  # 'restart' performs a `Kernel.exec`, reads the PID file and loads the new
  # value into `@pid`.
  #
  def restart_server
    run_pumactl 'restart'
    assert_io 'Restarting...'
    assert_io 'Ctrl-C'
    @pid = File.read(@path_pid, mode: 'rb').strip.to_i
  end

  # Waits for 'Ctrl-C'
  #
  def wait_for_server_to_boot
    assert_io 'Ctrl-C'  # wait for server to say it booted
  end

  # Opens a simple http connection.  Waits until "\\r\\n" is read/gotten.
  # @param path [String, nil] path to use
  # @return [TCPSocket, UNIXSocket]
  #
  def connect(path = nil)
    s = @bind == :unix ?
      UNIXSocket.new(@path_bind) :
      TCPSocket.new(HOST, @port_bind)

    @ios_to_close << s
    s << "GET /#{path} HTTP/1.1\r\n\r\n"
    true until s.gets == "\r\n"
    s
  end

  # Returns the body of a simple http connection.
  # @param arg [:IO, :String, nil] if IO, uses it for reading, if a string,
  #   opens the connection with the arg as the path, if nil, path is nil for a
  #   new connection
  # @return [String, nil] returns the body or nil on timeout
  #
  def read_body(arg = nil)
    connection = case arg
    when IO       then arg
    when String   then connect arg
    when NilClass then connect
    else
      raise ArgumentError, "read_body arg must be IO, String, or nil"
    end

    loop do
      break unless IO.select [connection], nil, nil, 10
      response = connection.readpartial(1024)
      body = response.split("\r\n\r\n", 2).last
      return body if body && !body.empty?
      sleep 0.01
    end
  end

  # gets worker pids from @server output
  def get_worker_pids(phase = 0, size = WORKERS)
    pids = []
    re = /pid: (\d+)\) booted, phase: #{phase}/
    while pids.size < size
      if pid = @server.gets[re, 1]
        pids << pid
      else
        sleep 2
      end
    end
    pids.map(&:to_i)
  end

  # Send requests 10 per second.  Send 10, then :TERM server, then send another 30.
  # No more than 10 should throw Errno::ECONNRESET.
  def stop_closes_listeners(args = nil)
    threads = []
    replies = []
    mutex = Mutex.new
    div   = 10

    cli_server "#{args} -q test/rackup/sleep_step.ru"

    refused = thread_run_refused

    41.times.each do |i|
      if i == 10
        threads << Thread.new do
          sleep i.to_f/div
          run_pumactl 'stop'
          mutex.synchronize { replies[i] = :term_sent }
        end
      else
        threads << Thread.new do
          thread_run_step replies, i.to_f/div, 1, i, mutex, refused
        end
      end
    end

    threads.each(&:join)

    failures  = replies.count(:failure)
    successes = replies.count(:success)
    resets    = replies.count(:reset)
    refused   = replies.count(:refused)

    r_success = replies.rindex(:success)
    l_reset   = replies.index(:reset)
    r_reset   = replies.rindex(:reset)
    l_refused = replies.index(:refused)

    msg = "#{successes} successes, #{resets} resets, #{refused} refused, failures #{failures}"

    assert_equal 0, failures, msg
    assert_equal 0, resets  , msg

    # successes are sometimes between 9 and 11 on macOS
    assert_operator  9, :<=, successes, msg
    assert_operator 29, :<=, refused  , msg

    # Interleaved asserts
    # UNIX binders do not generate :reset items
    if l_reset
      assert_operator r_success, :<, l_reset  , "Interleaved success and reset"
      assert_operator r_reset  , :<, l_refused, "Interleaved reset and refused"
    else
      assert_operator r_success, :<, l_refused, "Interleaved success and refused"
    end
  end

  # used with thread_run to define correct 'refused' errors
  def thread_run_refused
    if @bind == :unix
      DARWIN ? [Errno::ENOENT, IOError] : [Errno::ENOENT]
    elsif @bind == :tcp
      DARWIN ? [Errno::ECONNREFUSED, Errno::EPIPE, EOFError, IOError] :
        [Errno::ECONNREFUSED]
    end
  end

  # Used in #stop_closes_listeners
  def thread_run_step(replies, delay, sleep_time, step, mutex, refused)
    begin
      sleep delay
      body = read_body "sleep#{sleep_time}-#{step}"
      if body[/\ASlept /]
        mutex.synchronize { replies[step] = :success }
      else
        mutex.synchronize { replies[step] = :failure }
      end
    rescue Errno::ECONNRESET
      # connection was accepted but then closed
      # client would see an empty response
      mutex.synchronize { replies[step] = :reset }
    rescue *refused
      mutex.synchronize { replies[step] = :refused }
    end
  end
end
