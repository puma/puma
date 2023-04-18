# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/tmp_path"
require_relative "helpers/puma_socket"

class TestPumaUnixSocket < Minitest::Test
  include TmpPath
  include PumaTest::PumaSocket

  App = lambda { |env| [200, {}, ["Works"]] }

  def teardown
    return if skipped?
    @server.stop(true)
  end

  def server_unix(type)
    @bind_path = type == :unix ? tmp_path('.sock') : "@TestPumaUnixSocket"
    @server = Puma::Server.new App, nil, {min_threads: 1}
    @server.add_unix_listener @bind_path
    @server.run
  end

  def test_server_unix
    skip_unless :unix
    server_unix :unix

    resp = send_http_read_response "GET / HTTP/1.0\r\nHost: blah.com\r\n\r\n"

    expected = "HTTP/1.0 200 OK\r\nContent-Length: 5\r\n\r\nWorks"

    assert_equal expected, resp
  end

  def test_server_aunix
    skip_unless :aunix
    server_unix :aunix

    resp = send_http_read_response "GET / HTTP/1.0\r\nHost: blah.com\r\n\r\n"

    expected = "HTTP/1.0 200 OK\r\nContent-Length: 5\r\n\r\nWorks"

    assert_equal expected, resp
  end
end
