require_relative "helper"

require "puma/cli"
require "puma/control_cli"
require "open3"

# These don't run on travis because they're too fragile

class TestIntegration < Minitest::Test

  def setup
    @state_path = "test/test_puma.state"
    @bind_path = "test/test_server.sock"
    @control_path = "test/test_control.sock"
    @token = "xxyyzz"

    @server = nil

    @wait, @ready = IO.pipe

    @events = Puma::Events.strings
    @events.on_booted { @ready << "!" }
  end

  def teardown
    File.unlink @state_path rescue nil
    File.unlink @bind_path rescue nil
    File.unlink @control_path rescue nil

    @wait.close
    @ready.close

    if @server
      Process.kill "INT", @server.pid
      begin
        Process.wait @server.pid
      rescue Errno::ECHILD
      end

      @server.close
    end
  end

  def server(argv)
    @tcp_port = next_port
    base = "#{Gem.ruby} -Ilib bin/puma"
    base.prepend("bundle exec ") if defined?(Bundler)
    cmd = "#{base} -b tcp://127.0.0.1:#{@tcp_port} #{argv}"
    @server = IO.popen(cmd, "r")

    wait_for_server_to_boot

    @server
  end

  def start_forked_server(argv)
    @tcp_port = next_port
    pid = fork do
      exec "#{Gem.ruby} -I lib/ bin/puma -b tcp://127.0.0.1:#{@tcp_port} #{argv}"
    end

    sleep 5
    pid
  end

  def stop_forked_server(pid)
    Process.kill(:TERM, pid)
    sleep 1
    Process.wait2(pid)
  end

  def restart_server_and_listen(argv)
    server(argv)
    s = connect
    initial_reply = read_body(s)
    restart_server(s)
    [initial_reply, read_body(connect)]
  end

  def signal(which)
    Process.kill which, @server.pid
  end

  def wait_booted
    @wait.sysread 1
  end

  # reuses an existing connection to make sure that works
  def restart_server(connection)
    signal :USR2

    connection.write "GET / HTTP/1.1\r\n\r\n" # trigger it to start by sending a new request

    wait_for_server_to_boot
  end

  def connect
    s = TCPSocket.new "localhost", @tcp_port
    s << "GET / HTTP/1.1\r\n\r\n"
    true until s.gets == "\r\n"
    s
  end

  def wait_for_server_to_boot
    true while @server.gets !~ /Ctrl-C/ # wait for server to say it booted
  end

  def read_body(connection)
    Timeout.timeout(10) do
      loop do
        response = connection.readpartial(1024)
        body = response.split("\r\n\r\n", 2).last
        return body if body && !body.empty?
        sleep 0.01
      end
    end
  end

  def test_stop_via_pumactl
    skip UNIX_SKT_MSG unless UNIX_SKT_EXIST

    conf = Puma::Configuration.new do |c|
      c.quiet
      c.state_path @state_path
      c.bind "unix://#{@bind_path}"
      c.activate_control_app "unix://#{@control_path}", :auth_token => @token
      c.rackup "test/rackup/hello.ru"
    end

    l = Puma::Launcher.new conf, :events => @events

    t = Thread.new do
      Thread.current.abort_on_exception = true
      l.run
    end

    wait_booted

    s = UNIXSocket.new @bind_path
    s << "GET / HTTP/1.0\r\n\r\n"
    assert_equal "Hello World", read_body(s)

    sout = StringIO.new

    ccli = Puma::ControlCLI.new %W!-S #{@state_path} stop!, sout

    ccli.run

    assert_kind_of Thread, t.join, "server didn't stop"
  end

  def test_phased_restart_via_pumactl
    skip NO_FORK_MSG unless HAS_FORK

    # hello-stuck-ci uses sleep 10, hello-stuck uses sleep 60
    rackup = "test/rackup/hello-stuck#{ ENV['CI'] ? '-ci' : '' }.ru"

    conf = Puma::Configuration.new do |c|
      c.quiet
      c.state_path @state_path
      c.bind "unix://#{@bind_path}"
      c.activate_control_app "unix://#{@control_path}", :auth_token => @token
      c.workers 2
      c.worker_shutdown_timeout 1
      c.rackup rackup
    end

    l = Puma::Launcher.new conf, :events => @events

    t = Thread.new do
      Thread.current.abort_on_exception = true
      l.run
    end

    wait_booted

    s = UNIXSocket.new @bind_path
    s << "GET / HTTP/1.0\r\n\r\n"

    sout = StringIO.new
    # Phased restart
    ccli = Puma::ControlCLI.new ["-S", @state_path, "phased-restart"], sout
    ccli.run

    done = false
    until done
      @events.stdout.rewind
      log = @events.stdout.readlines.join("")
      if log =~ /- Worker \d \(pid: \d+\) booted, phase: 1/
        assert_match(/TERM sent/, log)
        assert_match(/- Worker \d \(pid: \d+\) booted, phase: 1/, log)
        done = true
      end
    end
    # Stop
    ccli = Puma::ControlCLI.new ["-S", @state_path, "stop"], sout
    ccli.run

    assert_kind_of Thread, t.join, "server didn't stop"
  end

  def test_kill_unknown_via_pumactl
    skip_on :jruby

    # we run ls to get a 'safe' pid to pass off as puma in cli stop
    # do not want to accidently kill a valid other process
    io = IO.popen(windows? ? "dir" : "ls")
    safe_pid = io.pid
    Process.wait safe_pid

    sout = StringIO.new

    e = assert_raises SystemExit do
      ccli = Puma::ControlCLI.new %W!-p #{safe_pid} stop!, sout
      ccli.run
    end
    sout.rewind
    # windows bad URI(is not URI?)
    assert_match(/No pid '\d+' found|bad URI\(is not URI\?\)/, sout.readlines.join(""))
    assert_equal(1, e.status)
  end

  def test_restart_closes_keepalive_sockets
    skip_unless_signal_exist? :USR2
    _, new_reply = restart_server_and_listen("-q test/rackup/hello.ru")
    assert_equal "Hello World", new_reply
  end

  def test_restart_closes_keepalive_sockets_workers
    skip NO_FORK_MSG unless HAS_FORK
    _, new_reply = restart_server_and_listen("-q -w 2 test/rackup/hello.ru")
    assert_equal "Hello World", new_reply
  end

  def test_sigterm_closes_listeners_on_forked_servers
    skip NO_FORK_MSG unless HAS_FORK
    pid = start_forked_server("-w 2 -q test/rackup/1second.ru")
    threads = []
    initial_reply = nil
    next_replies = []
    condition_variable = ConditionVariable.new
    mutex = Mutex.new

    threads << Thread.new do
      s = connect
      mutex.synchronize { condition_variable.broadcast }
      initial_reply = read_body(s)
    end

    threads << Thread.new do
      mutex.synchronize {
        condition_variable.wait(mutex, 1)
        Process.kill("SIGTERM", pid)
      }
    end

    10.times.each do |i|
      threads << Thread.new do
        mutex.synchronize { condition_variable.wait(mutex, 1.5) }

        begin
          s = connect
          read_body(s)
          next_replies << :success
        rescue Errno::ECONNRESET
          # connection was accepted but then closed
          # client would see an empty response
          next_replies << :connection_reset
        rescue Errno::ECONNREFUSED
          # connection was was never accepted
          # it can therefore be re-tried before the
          # client receives an empty reponse
          next_replies << :connection_refused
        end
      end
    end

    threads.map(&:join)

    assert_equal "Hello World", initial_reply

    assert_includes next_replies, :connection_refused

    refute_includes next_replies, :connection_reset
  end

  # It does not share environments between multiple generations, which would break Dotenv
  def test_restart_restores_environment
    # jruby has a bug where setting `nil` into the ENV or `delete` do not change the
    # next workers ENV
    skip_on :jruby
    skip_unless_signal_exist? :USR2

    initial_reply, new_reply = restart_server_and_listen("-q test/rackup/hello-env.ru")

    assert_includes initial_reply, "Hello RAND"
    assert_includes new_reply, "Hello RAND"
    refute_equal initial_reply, new_reply
  end

  def test_term_signal_exit_code_in_single_mode
    skip NO_FORK_MSG unless HAS_FORK

    pid = start_forked_server("test/rackup/hello.ru")
    _, status = stop_forked_server(pid)

    assert_equal 15, status
  end

  def test_term_signal_exit_code_in_clustered_mode
    skip NO_FORK_MSG unless HAS_FORK

    pid = start_forked_server("-w 2 test/rackup/hello.ru")
    _, status = stop_forked_server(pid)

    assert_equal 15, status
  end

  def test_term_signal_suppress_in_single_mode
    skip NO_FORK_MSG unless HAS_FORK

    pid = start_forked_server("-C test/config/suppress_exception.rb test/rackup/hello.ru")
    _, status = stop_forked_server(pid)

    assert_equal 0, status
  end

  def test_term_signal_suppress_in_clustered_mode
    skip NO_FORK_MSG unless HAS_FORK

    server("-w 2 -C test/config/suppress_exception.rb test/rackup/hello.ru")

    Process.kill(:TERM, @server.pid)
    begin
      Process.wait @server.pid
    rescue Errno::ECHILD
    end
    status = $?.exitstatus

    assert_equal 0, status
    @server = nil # prevent `#teardown` from killing already killed server
  end

  def test_not_accepts_new_connections_after_term_signal
    skip_on :jruby, :windows

    server('test/rackup/10seconds.ru')

    _stdin, curl_stdout, _stderr, curl_wait_thread = Open3.popen3("curl 127.0.0.1:#{@tcp_port}")
    sleep 1 # ensure curl send a request

    Process.kill(:TERM, @server.pid)
    true while @server.gets !~ /Gracefully stopping/ # wait for server to begin graceful shutdown

    # Invoke a request which must be rejected
    _stdin, _stdout, rejected_curl_stderr, rejected_curl_wait_thread = Open3.popen3("curl 127.0.0.1:#{@tcp_port}")

    assert nil != Process.getpgid(@server.pid) # ensure server is still running
    assert nil != Process.getpgid(rejected_curl_wait_thread[:pid]) # ensure first curl invokation still in progress

    curl_wait_thread.join
    rejected_curl_wait_thread.join

    assert_match(/Hello World/, curl_stdout.read)
    assert_match(/Connection refused/, rejected_curl_stderr.read)

    Process.wait(@server.pid)
    @server = nil # prevent `#teardown` from killing already killed server
  end
end
