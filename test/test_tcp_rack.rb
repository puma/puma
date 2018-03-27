require_relative "helper"

class TestTCPRack < Minitest::Test

  def setup
    @port = UniquePort.call
    @host = "127.0.0.1"

    @events = Puma::Events.new STDOUT, STDERR
    @server = Puma::Server.new nil, @events
  end

  def teardown
    @server.stop(true)
  end

  def test_passes_the_socket
    @server.tcp_mode!

    body = "We sell hats for a discount!\n"

    @server.app = proc do |env, socket|
      socket << body
      socket.close
    end

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @port

    assert_equal body, sock.read
  end
end
