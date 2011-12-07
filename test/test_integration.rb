require 'test/unit'
require 'rubygems'
require 'socket'

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
    status = nil

    io = IO.popen "#{Gem.ruby} -Ilib bin/puma -S #{@state_path} -b unix://#{@bind_path} --control unix://#{@control_path} test/hello.ru 2>&1", "r"

    line = nil

    until /Use Ctrl-C to stop/ =~ line.to_s
      line = io.gets
      raise "error" unless line
    end

    sleep 1

    s = UNIXSocket.new @bind_path
    s << "GET / HTTP/1.0\r\n\r\n"
    assert_equal "Hello World", s.read.split("\r\n").last

    `#{Gem.ruby} -Ilib bin/pumactl -S #{@state_path} stop 2>&1`

    pid, status = Process.wait2(io.pid)

    assert_equal 0, status.to_i
  end
end
