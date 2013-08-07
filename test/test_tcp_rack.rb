require "rbconfig"
require 'test/unit'
require 'socket'
require 'openssl'

require 'puma/minissl'
require 'puma/server'

require 'net/https'

class TestTCPRack < Test::Unit::TestCase

  def setup
    @port = 3212
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
