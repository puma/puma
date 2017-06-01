require_relative "helper"

require "puma/cli"
require "puma/control_cli"

# These don't run on travis because they're too fragile

class TestIntegration < Minitest::Test
  def setup
    @state_path = "test/test_puma.state"
    @bind_path = "test/test_server.sock"
    @control_path = "test/test_control.sock"
    @token = "xxyyzz"
    @tcp_port = 9998

    @server = nil

    @wait, @ready = IO.pipe

    @events = Puma::Events.strings
    @events.on_booted { @ready << "!" }
  end

  def teardown
    File.unlink @state_path rescue nil
    File.unlink @bind_path  rescue nil
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
    # when we were started with bundler all load-paths and bin-paths are setup correctly
    # this is what 9X% of users run, so it is what we should test
    # the other case is solely for package builders or testing 1-off cases where the system puma is used
    base = (defined?(Bundler) ? "bundle exec puma" : "#{Gem.ruby} -Ilib bin/puma")
    cmd = "#{base} -b tcp://127.0.0.1:#{@tcp_port} #{argv}"
    @server = IO.popen(cmd, "r")

    wait_for_server_to_boot

    @server
  end

  def restart_server_and_listen(argv)
    server(argv)
    s = connect
    initial_reply = s.read
    restart_server(s)
    [initial_reply, connect.read]
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

    sleep 1

    connection.write "GET / HTTP/1.1\r\n\r\n" # trigger it to start by sending a new request

    assert_raises Errno::ECONNRESET do
      Timeout.timeout(2) do
        raise Errno::ECONNRESET unless connection.read(2)
      end
    end

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
    sleep(Puma.jruby? ? 5 : 1) # TODO: not sure why that is needed ... something deterministic would be better
  end

  def test_stop_via_pumactl
    if Puma.jruby? || Puma.windows?
      assert true
      return
    end

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
    assert_equal "Hello World", s.read.split("\r\n").last

    sout = StringIO.new

    ccli = Puma::ControlCLI.new %W!-S #{@state_path} stop!, sout

    ccli.run

    assert_kind_of Thread, t.join(1), "server didn't stop"
  end

  def test_phased_restart_via_pumactl
    skip("Too finicky, fails 50% of the time on CI") if ENV["CI"]

    if Puma.jruby? || Puma.windows?
      assert true
      return
    end

    conf = Puma::Configuration.new do |c|
      c.quiet
      c.state_path @state_path
      c.bind "unix://#{@bind_path}"
      c.activate_control_app "unix://#{@control_path}", :auth_token => @token
      c.workers 2
      c.worker_shutdown_timeout 1
      c.rackup "test/rackup/hello-stuck.ru"
    end

    l = Puma::Launcher.new conf, :events => @events

    Thread.abort_on_exception = true

    t = Thread.new do
      Thread.current.abort_on_exception = true
      l.run
    end

    wait_booted

    # Make both workers stuck
    s1 = UNIXSocket.new @bind_path
    s1 << "GET / HTTP/1.0\r\n\r\n"

    sout = StringIO.new

    # Phased restart
    ccli = Puma::ControlCLI.new %W!-S #{@state_path} phased-restart!, sout
    ccli.run
    sleep 20
    @events.stdout.rewind
    log = @events.stdout.readlines.join("")
    assert_match(/TERM sent/, log)
    assert_match(/- Worker \d \(pid: \d+\) booted, phase: 1/, log)

    # Stop
    ccli = Puma::ControlCLI.new %W!-S #{@state_path} stop!, sout
    ccli.run

    assert_kind_of Thread, t.join(5), "server didn't stop"
  end

  def test_kill_unknown_via_pumactl
    if Puma.jruby? || Puma.windows?
      assert true
      return
    end

    # we run ls to get a 'safe' pid to pass off as puma in cli stop
    # do not want to accidently kill a valid other process
    io = IO.popen("ls")
    safe_pid = io.pid
    Process.wait safe_pid

    sout = StringIO.new

    e = assert_raises SystemExit do
      ccli = Puma::ControlCLI.new %W!-p #{safe_pid} stop!, sout
      ccli.run
    end
    sout.rewind
    assert_match(/No pid '\d+' found/, sout.readlines.join(""))
    assert_equal(1, e.status)
  end

  def test_restart_closes_keepalive_sockets
    _, new_reply = restart_server_and_listen("-q test/rackup/hello.ru")
    assert_equal "Hello World", new_reply
  end

  def test_restart_closes_keepalive_sockets_workers
    if Puma.jruby?
      assert true
      return
    end

    _, new_reply = restart_server_and_listen("-q -w 2 test/rackup/hello.ru")
    assert_equal "Hello World", new_reply
  end

  # It does not share environments between multiple generations, which would break Dotenv
  def test_restart_restores_environment
    if Puma.jruby?
      # jruby has a bug where setting `nil` into the ENV or `delete` do not change the
      # next workers ENV
      assert true
      return
    end

    initial_reply, new_reply = restart_server_and_listen("-q test/rackup/hello-env.ru")

    assert_includes initial_reply, "Hello RAND"
    assert_includes new_reply, "Hello RAND"
    refute_equal initial_reply, new_reply
  end
end
