require "rbconfig"
require 'test/unit'
require 'socket'

require 'puma/cli'
require 'puma/control_cli'

class TestIntegration < Test::Unit::TestCase
  def setup
    @state_path = "test/test_puma.state"
    @bind_path = "test/test_server.sock"
    @control_path = "test/test_control.sock"
  end

  def teardown
    File.unlink @state_path rescue nil
    File.unlink @bind_path  rescue nil
    File.unlink @control_path rescue nil
  end

  def test_stop_via_pumactl
    if defined?(JRUBY_VERSION) || RbConfig::CONFIG["host_os"] =~ /mingw|mswin/
      assert true
      return
    end

    sin = StringIO.new
    sout = StringIO.new

    cli = Puma::CLI.new %W!-q -S #{@state_path} -b unix://#{@bind_path} --control unix://#{@control_path} test/hello.ru!, sin, sout

    t = Thread.new do
      cli.run
    end

    sleep 1

    s = UNIXSocket.new @bind_path
    s << "GET / HTTP/1.0\r\n\r\n"
    assert_equal "Hello World", s.read.split("\r\n").last

    ccli = Puma::ControlCLI.new %W!-S #{@state_path} stop!, sout

    ccli.run

    assert_kind_of Thread, t.join(1), "server didn't stop"
  end
end
