# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/tmp_path"

class TestPumaUnixSocket < Minitest::Test
  include TmpPath

  App = lambda { |env| [200, {}, ["Works"]] }

  def teardown
    return if skipped?
    @server.stop(true)
  end

  def server_unix(type)
    @tmp_socket_path = type == :unix ? tmp_path('.sock') : "@TestPumaUnixSocket"
    @server = Puma::Server.new App
    @server.add_unix_listener @tmp_socket_path
    @server.run
  end

  def test_server_unix
    skip_unless :unix
    server_unix :unix
    sock = UNIXSocket.new @tmp_socket_path

    sock << "GET / HTTP/1.0\r\nHost: blah.com\r\n\r\n"

    expected = "HTTP/1.0 200 OK\r\ncontent-length: 5\r\n\r\nWorks"

    assert_equal expected, sock.read(expected.size)
  end

  def test_server_aunix
    skip_unless :aunix
    server_unix :aunix
    sock = UNIXSocket.new @tmp_socket_path.sub(/\A@/, "\0")

    sock << "GET / HTTP/1.0\r\nHost: blah.com\r\n\r\n"

    expected = "HTTP/1.0 200 OK\r\ncontent-length: 5\r\n\r\nWorks"

    assert_equal expected, sock.read(expected.size)
  end
end
