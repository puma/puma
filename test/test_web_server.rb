# frozen_string_literal: true
# Copyright (c) 2011 Evan Phoenix
# Copyright (c) 2005 Zed A. Shaw

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

  VALID_REQUEST = "GET / HTTP/1.1\r\nHost: www.zedshaw.com\r\nContent-Type: text/plain\r\n\r\n"

  def setup
    @tester = TestHandler.new
    @server = Puma::Server.new @tester, Puma::Events.strings
    @server.add_tcp_listener "127.0.0.1", 0

    @server.run
  end

  def teardown
    @server.stop(true)
  end

  def test_simple_server
    hit(["http://127.0.0.1:#{@server.connected_port}/test"])
    assert @tester.ran_test, "Handler didn't really run"
  end

  def test_trickle_attack
    socket = do_test(VALID_REQUEST, 3)
    assert_match "hello", socket.read
    socket.close
  end

  def test_close_client
    assert_raises IOError do
      do_test_raise(VALID_REQUEST, 10, 20)
    end
  end

  def test_bad_client
    socket = do_test("GET /test HTTP/BAD", 3)
    assert_match "Bad Request", socket.read
    socket.close
  end

  def test_header_is_too_long
    long = "GET /test HTTP/1.1\r\n" + ("X-Big: stuff\r\n" * 15000) + "\r\n"
    assert_raises Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNABORTED, Errno::EINVAL, IOError do
      do_test_raise(long, long.length/2, 10)
    end
  end

  # TODO: Why does this test take exactly 20 seconds?
  def test_file_streamed_request
    body = "a" * (Puma::Const::MAX_BODY * 2)
    long = "GET /test HTTP/1.1\r\nContent-length: #{body.length}\r\n\r\n" + body
    socket = do_test(long, (Puma::Const::CHUNK_SIZE * 2) - 400)
    assert_match "hello", socket.read
    socket.close
  end

  private

  def do_test(string, chunk)
    # Do not use instance variables here, because it needs to be thread safe
    socket = TCPSocket.new("127.0.0.1", @server.connected_port);
    request = StringIO.new(string)
    chunks_out = 0

    while data = request.read(chunk)
      chunks_out += socket.write(data)
      socket.flush
    end
    socket
  end

  def do_test_raise(string, chunk, close_after = nil)
    # Do not use instance variables here, because it needs to be thread safe
    socket = TCPSocket.new("127.0.0.1", @server.connected_port);
    request = StringIO.new(string)
    chunks_out = 0

    while data = request.read(chunk)
      chunks_out += socket.write(data)
      socket.flush
      socket.close if close_after && chunks_out > close_after
    end

    socket.write(" ") # Some platforms only raise the exception on attempted write
    socket.flush
    socket
  ensure
    socket.close unless socket.closed?
  end
end
