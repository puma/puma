# frozen_string_literal: true

require_relative "helper"

class TestPumaUnixSocket < Minitest::Test

  App = lambda { |env| [200, {}, ["Works"]] }

  PATH = tmp_path('.sock')

  def setup
    return unless UNIX_SKT_EXIST
    @server = Puma::Server.new App
    @server.add_unix_listener PATH
    @server.run
  end

  def teardown
    return unless UNIX_SKT_EXIST
    @server.stop(true)
  end

  def test_server
    skip UNIX_SKT_MSG unless UNIX_SKT_EXIST
    sock = UNIXSocket.new PATH

    sock << "GET / HTTP/1.0\r\nHost: blah.com\r\n\r\n"

    expected = "HTTP/1.0 200 OK\r\nContent-Length: 5\r\n\r\nWorks"

    assert_equal expected, sock.read(expected.size)
  end
end
