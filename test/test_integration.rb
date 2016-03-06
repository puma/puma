require "rbconfig"
require 'test/unit'
require 'socket'
require 'timeout'
require 'net/http'
require 'tempfile'

require 'puma/cli'
require 'puma/control_cli'
require 'puma/detect'

# These don't run on travis because they're too fragile

class TestIntegration < Test::Unit::TestCase
  def setup
    @state_path = "test/test_puma.state"
    @bind_path = "test/test_server.sock"
    @control_path = "test/test_control.sock"
    @token = "xxyyzz"
    @tcp_port = 9998

    @server = nil
    @script = nil

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

    if @script
      @script.close!
    end
  end

  def server(opts)
    core = "#{Gem.ruby} -rubygems -Ilib bin/puma"
    cmd = "#{core} --restart-cmd '#{core}' -b tcp://127.0.0.1:#{@tcp_port} #{opts}"
    tf = Tempfile.new "puma-test"
    tf.puts "exec #{cmd}"
    tf.close

    @script = tf

    @server = IO.popen("sh #{tf.path}", "r")

    while (l = @server.gets) !~ /Ctrl-C/
      # nothing
    end

    sleep 1

    @server
  end

  def signal(which)
    Process.kill which, @server.pid
  end

  def wait_booted
    @wait.sysread 1
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
      c.rackup "test/hello.ru"
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
      c.rackup "test/hello-stuck.ru"
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
    assert_match(/Worker \d \(pid: \d+\) booted, phase: 1/, log)

    # Stop
    ccli = Puma::ControlCLI.new %W!-S #{@state_path} stop!, sout
    ccli.run

    assert_kind_of Thread, t.join(5), "server didn't stop"
  end

  def test_restart_closes_keepalive_sockets
    server("-q test/hello.ru")

    s = TCPSocket.new "localhost", @tcp_port
    s << "GET / HTTP/1.1\r\n\r\n"
    true until s.gets == "\r\n"

    s.readpartial(20)
    signal :USR2

    sleep 1

    s.write "GET / HTTP/1.1\r\n\r\n"

    e = assert_raises Errno::ECONNRESET do
      Timeout.timeout(2) do
        raise Errno::ECONNRESET unless s.read(2)
      end
    end

    while (l = @server.gets) !~ /Ctrl-C/
      # nothing
    end

    sleep 5 if Puma.jruby?

    s = TCPSocket.new "127.0.0.1", @tcp_port
    s << "GET / HTTP/1.0\r\n\r\n"
    assert_equal "Hello World", s.read.split("\r\n").last
  end

  def test_restart_closes_keepalive_sockets_workers
    if Puma.jruby?
      assert true
      return
    end

    server("-q -w 2 test/hello.ru")

    s = TCPSocket.new "localhost", @tcp_port
    s << "GET / HTTP/1.1\r\n\r\n"
    true until s.gets == "\r\n"

    s.readpartial(20)
    signal :USR2

    true while @server.gets =~ /Ctrl-C/
    sleep 1

    s.write "GET / HTTP/1.1\r\n\r\n"

    assert_raises Errno::ECONNRESET do
      Timeout.timeout(2) do
        raise Errno::ECONNRESET unless s.read(2)
      end
    end

    s = TCPSocket.new "localhost", @tcp_port
    s << "GET / HTTP/1.0\r\n\r\n"
    assert_equal "Hello World", s.read.split("\r\n").last
  end

  def test_bad_query_string_outputs_400
    server "-q test/hello.ru 2>&1"

    s = TCPSocket.new "localhost", @tcp_port
    s << "GET /?h=% HTTP/1.0\r\n\r\n"
    data = s.read
    assert_equal "HTTP/1.1 400 Bad Request\r\n\r\n", data
  end
end
