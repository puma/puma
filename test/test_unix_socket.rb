require 'test/unit'
require 'puma/server'

require 'socket'

class TestPumaUnixSocket < Test::Unit::TestCase

  App = lambda { |env| [200, {}, ["Works"]] }

  Path = "test/puma.sock"

  def setup
    @server = Puma::Server.new App, 2
  end

  def teardown
    @server.stop(true)
    File.unlink Path if File.exists? Path
  end

  def test_server
    @server.add_unix_listener Path
    @server.run

    sock = UNIXSocket.new Path

    sock << "GET / HTTP/1.0\r\nHost: blah.com\r\n\r\n"

    assert_equal "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\nWorks",
                 sock.read
  end
end
