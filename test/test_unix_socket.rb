# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/test_puma/server_in_process"

class TestPumaUnixSocket < TestPuma::ServerInProcess

  def server_unix
    server_run app: ->(_) { [200, {}, ["Works"]] }
    @req = "GET / HTTP/1.0\r\nHost: blah.com\r\n\r\n"
    @expected = "HTTP/1.0 200 OK\r\nContent-Length: 5\r\n\r\nWorks"
  end

  def test_server_unix
    set_bind_type :unix
    server_unix
    assert_equal @expected, send_http_read_response(@req)
  end

  def test_server_aunix
    set_bind_type :aunix
    server_unix
    assert_equal @expected, send_http_read_response(@req)
  end
end
