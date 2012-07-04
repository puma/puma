# Copyright (c) 2011 Evan Phoenix
# Copyright (c) 2005 Zed A. Shaw 

require 'test/testhelp'

include Puma

class TestHandler
  attr_reader :ran_test

  def call(env)
    @ran_test = true

    [200, {"Content-Type" => "text/plain"}, ["hello!"]]
  end
end

class WebServerTest < Test::Unit::TestCase

  def setup
    @valid_request = "GET / HTTP/1.1\r\nHost: www.zedshaw.com\r\nContent-Type: text/plain\r\n\r\n"
    
    @tester = TestHandler.new

    @server = Server.new @tester, Events.strings
    @server.add_tcp_listener "127.0.0.1", 9998

    @server.run
  end

  def teardown
    @server.stop(true)
  end

  def test_simple_server
    hit(['http://127.0.0.1:9998/test'])
    assert @tester.ran_test, "Handler didn't really run"
  end


  def do_test(string, chunk, close_after=nil, shutdown_delay=0)
    # Do not use instance variables here, because it needs to be thread safe
    socket = TCPSocket.new("127.0.0.1", 9998);
    request = StringIO.new(string)
    chunks_out = 0

    while data = request.read(chunk)
      chunks_out += socket.write(data)
      socket.flush
      sleep 0.2
      if close_after and chunks_out > close_after
        socket.close
        sleep 1
      end
    end
    sleep(shutdown_delay)
    socket.write(" ") # Some platforms only raise the exception on attempted write
    socket.flush
  end

  def test_trickle_attack
    do_test(@valid_request, 3)
  end

  def test_close_client
    assert_raises IOError do
      do_test(@valid_request, 10, 20)
    end
  end

  def test_bad_client
    do_test("GET /test HTTP/BAD", 3)
  end

  def test_header_is_too_long
    long = "GET /test HTTP/1.1\r\n" + ("X-Big: stuff\r\n" * 15000) + "\r\n"
    assert_raises Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNABORTED, Errno::EINVAL, IOError do
      do_test(long, long.length/2, 10)
    end
  end

  def test_file_streamed_request
    body = "a" * (Puma::Const::MAX_BODY * 2)
    long = "GET /test HTTP/1.1\r\nContent-length: #{body.length}\r\n\r\n" + body
    do_test(long, (Puma::Const::CHUNK_SIZE * 2) - 400)
  end

end

