# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/tmp_path"

class TestPumaUnixSocket < Minitest::Test
  include TmpPath

  App = lambda { |env| [200, {}, ["Works"]] }

  def setup
    return unless UNIX_SKT_EXIST
    @tmp_socket_path = tmp_path('.sock')
    @server = Puma::Server.new App
    @server.add_unix_listener @tmp_socket_path
    @server.run
  end

  def teardown
    return unless UNIX_SKT_EXIST
    @server.stop(true)
  end

  def test_server
    skip UNIX_SKT_MSG unless UNIX_SKT_EXIST
    sock = UNIXSocket.new @tmp_socket_path

    sock.syswrite "GET / HTTP/1.0\r\nHost: blah.com\r\n\r\n"

    expected = "HTTP/1.0 200 OK\r\nContent-Length: 5\r\n\r\nWorks"

    assert_equal expected, sock.read(expected.size)
  end
end
