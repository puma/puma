# frozen_string_literal: true

require_relative "helper"

require "puma/server"

class TestHandler
  attr_reader :ran_test

  def call(env)
    @ran_test = true

    [200, {"Content-Type" => "text/plain"}, ["hello!"]]
  end
end

class WebServerTest < Minitest::Test
  parallelize_me!

  def run_server(options: {})
    @tester = TestHandler.new
    @server = Puma::Server.new @tester, nil, options
    @port = (@server.add_tcp_listener "127.0.0.1", 0).addr[1]
    @tcp = "http://127.0.0.1:#{@port}"
    @server.run
  end

  def teardown
    @server.stop(true)
  end

  def test_unsupported_method
    run_server
    socket = do_test("CONNECT www.zedshaw.com:443 HTTP/1.1\r\nConnection: close\r\n\r\n", 100)
    response = socket.read
    assert_match "501 Not Implemented", response
    socket.close
  end

  def test_nonexistent_method
    run_server
    socket = do_test("FOOBARBAZ www.zedshaw.com:443 HTTP/1.1\r\nConnection: close\r\n\r\n", 100)
    response = socket.read
    assert_match "501 Not Implemented", response
    socket.close
  end

  def test_custom_declared_method
    run_server(options: { supported_http_methods: ["FOOBARBAZ"] })
    socket = do_test("FOOBARBAZ www.zedshaw.com:443 HTTP/1.1\r\nConnection: close\r\n\r\n", 100)
    response = socket.read
    assert_match "HTTP/1.1 200 OK", response
    socket.close
  end

  private

  def do_test(string, chunk)
    # Do not use instance variables here, because it needs to be thread safe
    socket = TCPSocket.new("127.0.0.1", @port)
    request = StringIO.new(string)
    chunks_out = 0

    while data = request.read(chunk)
      chunks_out += socket.write(data)
      socket.flush
    end
    socket
  end
end
