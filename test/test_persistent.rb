require 'puma'
require 'test/unit'

class TestPersistent < Test::Unit::TestCase
  def setup
    @valid_request = "GET / HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\n\r\n"
    @close_request = "GET / HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n"

    @headers = { "X-Header" => "Works" }
    @body = ["Hello"]
    @simple = lambda { |env| [200, @headers, @body] }
    @server = Puma::Server.new @simple
    @server.add_tcp_listener "127.0.0.1", 9988
    @server.run

    @client = TCPSocket.new "127.0.0.1", 9988
  end

  def teardown
    @client.close
    @server.stop(true)
  end

  def lines(count, s=@client)
    str = ""
    count.times { str << s.gets }
    str
  end

  def test_one_with_content_length
    @client << @valid_request
    sz = @body[0].size.to_s

    assert_equal "HTTP/1.1 200 OK\r\nContent-Length: #{sz}\r\nX-Header: Works\r\n\r\n", lines(4)
    assert_equal "Hello", @client.read(5)
  end

  def test_two_back_to_back
    @client << @valid_request
    sz = @body[0].size.to_s

    assert_equal "HTTP/1.1 200 OK\r\nContent-Length: #{sz}\r\nX-Header: Works\r\n\r\n", lines(4)
    assert_equal "Hello", @client.read(5)

    @client << @valid_request
    sz = @body[0].size.to_s

    assert_equal "HTTP/1.1 200 OK\r\nContent-Length: #{sz}\r\nX-Header: Works\r\n\r\n", lines(4)
    assert_equal "Hello", @client.read(5)
  end

  def test_chunked
    @body << "Chunked"

    @client << @valid_request

    assert_equal "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nX-Header: Works\r\n\r\n5\r\nHello\r\n7\r\nChunked\r\n0\r\n", lines(9)
  end

  def test_hex
    str = "This is longer and will be in hex"
    @body << str

    @client << @valid_request

    assert_equal "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nX-Header: Works\r\n\r\n5\r\nHello\r\n#{str.size.to_s(16)}\r\n#{str}\r\n0\r\n", lines(9)

  end

  def test_client_close
    @client << @close_request
    sz = @body[0].size.to_s

    assert_equal "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: #{sz}\r\nX-Header: Works\r\n\r\n", lines(5)
    assert_equal "Hello", @client.read(5)
  end

end
