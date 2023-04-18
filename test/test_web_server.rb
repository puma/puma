# frozen_string_literal: true
# Copyright (c) 2011 Evan Phoenix
# Copyright (c) 2005 Zed A. Shaw

require_relative "helper"
require_relative "helpers/puma_socket"

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

  include PumaTest::PumaSocket

  VALID_REQUEST = "GET / HTTP/1.1\r\nHost: www.zedshaw.com\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n"

  def setup
    @host = '127.0.0.1'
    @tester = TestHandler.new
    @server = Puma::Server.new @tester, nil, {log_writer: Puma::LogWriter.strings}
    @port = (@server.add_tcp_listener @host, 0).addr[1]
    @tcp = "http://#{@host}:#{@port}"
    @server.run
  end

  def teardown
    @server.stop(true)
  end

  def test_simple_server
    send_http_read_response "GET /test HTTP/1.1\r\n\r\n"
    assert @tester.ran_test, "Handler didn't really run"
  end

  def test_requests_count
    req = "GET /test HTTP/1.1\r\n\r\n"
    assert_equal @server.requests_count, 0
    3.times { send_http_read_response req }
    assert_equal 3, @server.requests_count
  end

  def test_trickle_attack
    assert_match "hello", do_test(VALID_REQUEST, 3)
  end

  def test_close_client
    assert_raises IOError do
      do_test_raise(VALID_REQUEST, 10, 20)
    end
  end

  def test_bad_client
    assert_match "Bad Request", do_test("GET /test HTTP/BAD", 3)
  end

  def test_header_is_too_long
    long = "GET /test HTTP/1.1\r\n" + ("X-Big: stuff\r\n" * 15000) + "\r\n"
    assert_raises Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNABORTED, Errno::EINVAL, IOError do
      do_test_raise(long, long.length/2, 10)
    end
  end

  def test_file_streamed_request
    req_body = "a" * (Puma::Const::MAX_BODY * 2)
    req = "GET /test HTTP/1.1\r\nContent-length: #{req_body.length}\r\nConnection: close\r\n\r\n#{req_body}"
    assert_match "hello", do_test(req, (Puma::Const::CHUNK_SIZE * 2) - 400)
  end

  def test_unsupported_method
    req = "CONNECT www.zedshaw.com:443 HTTP/1.1\r\nConnection: close\r\n\r\n"
    assert_match "Not Implemented", do_test(req, 100)
  end

  def test_nonexistent_method
    req = "FOOBARBAZ www.zedshaw.com:443 HTTP/1.1\r\nConnection: close\r\n\r\n"
    assert_match "Not Implemented", do_test(req, 100)
  end

  private

  def do_test(string, chunk)
    # Do not use instance variables here, because it needs to be thread safe
    socket = new_connection
    request = StringIO.new(string)
    chunks_out = 0

    while data = request.read(chunk)
      chunks_out += socket.syswrite(data)
    end
    socket.read_response
  end

  def do_test_raise(string, chunk, close_after = nil)
    # Do not use instance variables here, because it needs to be thread safe
    socket = new_connection
    request = StringIO.new(string)
    chunks_out = 0

    while data = request.read(chunk)
      chunks_out += socket.syswrite(data)
      socket.close if close_after && chunks_out > close_after
    end

    socket << " " # Some platforms only raise the exception on attempted write
    socket.read_response
  end
end
