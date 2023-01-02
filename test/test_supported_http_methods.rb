# frozen_string_literal: true

require_relative "helper"

require "puma/server"

class WebServerTest < Minitest::Test
  def run_server(options: {})
    app = ->(_env) { [200, {}, []] }

    @server = Puma::Server.new app, nil, options
    @port = (@server.add_tcp_listener "127.0.0.1", 0).addr[1]
    @server.run
  end

  def teardown
    @server.stop(true)
  end

  def test_unsupported_method
    run_server
    response = send_http_and_read("CONNECT www.zedshaw.com:443 HTTP/1.1\r\nConnection: close\r\n\r\n")
    assert_match "501 Not Implemented", response
  end

  def test_nonexistent_method
    run_server
    response = send_http_and_read("FOOBARBAZ www.zedshaw.com:443 HTTP/1.1\r\nConnection: close\r\n\r\n")
    assert_match "501 Not Implemented", response
  end

  def test_custom_declared_method
    run_server(options: { supported_http_methods: ["FOOBARBAZ"].zip([nil]).to_h.freeze })
    response = send_http_and_read("FOOBARBAZ www.zedshaw.com:443 HTTP/1.1\r\nConnection: close\r\n\r\n")
    assert_match "HTTP/1.1 200 OK", response
  end

  private

  def send_http_and_read(req)
    socket = TCPSocket.new("127.0.0.1", @port)
    socket << req
    socket.read
  end
end
