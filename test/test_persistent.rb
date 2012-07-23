require 'puma'
require 'test/unit'
require 'timeout'

class TestPersistent < Test::Unit::TestCase
  def setup
    @valid_request = "GET / HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\n\r\n"
    @close_request = "GET / HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n"
    @http10_request = "GET / HTTP/1.0\r\nHost: test.com\r\nContent-Type: text/plain\r\n\r\n"
    @keep_request = "GET / HTTP/1.0\r\nHost: test.com\r\nContent-Type: text/plain\r\nConnection: Keep-Alive\r\n\r\n"

    @valid_post = "POST / HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nhello"
    @valid_no_body = "GET / HTTP/1.1\r\nHost: test.com\r\nX-Status: 204\r\nContent-Type: text/plain\r\n\r\n"

    @headers = { "X-Header" => "Works" }
    @body = ["Hello"]
    @inputs = []

    @simple = lambda do |env|
      @inputs << env['rack.input']
      status = Integer(env['HTTP_X_STATUS'] || 200)
      [status, @headers, @body]
    end

    @host = "127.0.0.1"
    @port = 9988

    @server = Puma::Server.new @simple
    @server.add_tcp_listener "127.0.0.1", 9988
    @server.max_threads = 1
    @server.run

    @client = TCPSocket.new "127.0.0.1", 9988
  end

  def teardown
    @client.close
    @server.stop(true)
  end

  def lines(count, s=@client)
    str = ""
    timeout(5) do
      count.times { str << s.gets }
    end
    str
  end

  def test_one_with_content_length
    @client << @valid_request
    sz = @body[0].size.to_s

    assert_equal "HTTP/1.1 200 OK\r\nX-Header: Works\r\nContent-Length: #{sz}\r\n\r\n", lines(4)
    assert_equal "Hello", @client.read(5)
  end

  def test_two_back_to_back
    @client << @valid_request
    sz = @body[0].size.to_s

    assert_equal "HTTP/1.1 200 OK\r\nX-Header: Works\r\nContent-Length: #{sz}\r\n\r\n", lines(4)
    assert_equal "Hello", @client.read(5)

    @client << @valid_request
    sz = @body[0].size.to_s

    assert_equal "HTTP/1.1 200 OK\r\nX-Header: Works\r\nContent-Length: #{sz}\r\n\r\n", lines(4)
    assert_equal "Hello", @client.read(5)
  end

  def test_post_then_get
    @client << @valid_post
    sz = @body[0].size.to_s

    assert_equal "HTTP/1.1 200 OK\r\nX-Header: Works\r\nContent-Length: #{sz}\r\n\r\n", lines(4)
    assert_equal "Hello", @client.read(5)

    @client << @valid_request
    sz = @body[0].size.to_s

    assert_equal "HTTP/1.1 200 OK\r\nX-Header: Works\r\nContent-Length: #{sz}\r\n\r\n", lines(4)
    assert_equal "Hello", @client.read(5)
  end

  def test_no_body_then_get
    @client << @valid_no_body
    assert_equal "HTTP/1.1 204 No Content\r\nX-Header: Works\r\n\r\n", lines(3)

    @client << @valid_request
    sz = @body[0].size.to_s

    assert_equal "HTTP/1.1 200 OK\r\nX-Header: Works\r\nContent-Length: #{sz}\r\n\r\n", lines(4)
    assert_equal "Hello", @client.read(5)
  end

  def test_chunked
    @body << "Chunked"

    @client << @valid_request

    assert_equal "HTTP/1.1 200 OK\r\nX-Header: Works\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nHello\r\n7\r\nChunked\r\n0\r\n\r\n", lines(10)
  end

  def test_no_chunked_in_http10
    @body << "Chunked"

    @client << @http10_request

    assert_equal "HTTP/1.0 200 OK\r\nX-Header: Works\r\nConnection: close\r\n\r\n", lines(4)
    assert_equal "HelloChunked", @client.read
  end

  def test_hex
    str = "This is longer and will be in hex"
    @body << str

    @client << @valid_request

    assert_equal "HTTP/1.1 200 OK\r\nX-Header: Works\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nHello\r\n#{str.size.to_s(16)}\r\n#{str}\r\n0\r\n\r\n", lines(10)

  end

  def test_client11_close
    @client << @close_request
    sz = @body[0].size.to_s

    assert_equal "HTTP/1.1 200 OK\r\nX-Header: Works\r\nConnection: close\r\nContent-Length: #{sz}\r\n\r\n", lines(5)
    assert_equal "Hello", @client.read(5)
  end

  def test_client10_close
    @client << @http10_request
    sz = @body[0].size.to_s

    assert_equal "HTTP/1.0 200 OK\r\nX-Header: Works\r\nConnection: close\r\nContent-Length: #{sz}\r\n\r\n", lines(5)
    assert_equal "Hello", @client.read(5)
  end

  def test_one_with_keep_alive_header
    @client << @keep_request
    sz = @body[0].size.to_s

    assert_equal "HTTP/1.0 200 OK\r\nX-Header: Works\r\nConnection: Keep-Alive\r\nContent-Length: #{sz}\r\n\r\n", lines(5)
    assert_equal "Hello", @client.read(5)
  end

  def test_persistent_timeout
    @server.persistent_timeout = 2
    @client << @valid_request
    sz = @body[0].size.to_s

    assert_equal "HTTP/1.1 200 OK\r\nX-Header: Works\r\nContent-Length: #{sz}\r\n\r\n", lines(4)
    assert_equal "Hello", @client.read(5)

    sleep 3

    assert_raises EOFError do
      @client.read_nonblock(1)
    end
  end

  def test_app_sets_content_length
    @body = ["hello", " world"]
    @headers['Content-Length'] = "11"

    @client << @valid_request

    assert_equal "HTTP/1.1 200 OK\r\nX-Header: Works\r\nContent-Length: 11\r\n\r\n",
                 lines(4)
    assert_equal "hello world", @client.read(11)
  end

  def test_allow_app_to_chunk_itself
    @headers = {'Transfer-Encoding' => "chunked" }

    @body = ["5\r\nhello\r\n0\r\n\r\n"]

    @client << @valid_request

    assert_equal "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n", lines(7)
  end


  def test_two_requests_in_one_chunk
    @server.persistent_timeout = 3

    req = @valid_request.to_s
    req << "GET /second HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\n\r\n"

    @client << req

    sz = @body[0].size.to_s

    assert_equal "HTTP/1.1 200 OK\r\nX-Header: Works\r\nContent-Length: #{sz}\r\n\r\n", lines(4)
    assert_equal "Hello", @client.read(5)

    assert_equal "HTTP/1.1 200 OK\r\nX-Header: Works\r\nContent-Length: #{sz}\r\n\r\n", lines(4)
    assert_equal "Hello", @client.read(5)
  end

  def test_second_request_not_in_first_req_body
    @server.persistent_timeout = 3

    req = @valid_request.to_s
    req << "GET /second HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\n\r\n"

    @client << req

    sz = @body[0].size.to_s

    assert_equal "HTTP/1.1 200 OK\r\nX-Header: Works\r\nContent-Length: #{sz}\r\n\r\n", lines(4)
    assert_equal "Hello", @client.read(5)

    assert_equal "HTTP/1.1 200 OK\r\nX-Header: Works\r\nContent-Length: #{sz}\r\n\r\n", lines(4)
    assert_equal "Hello", @client.read(5)

    assert_kind_of Puma::NullIO, @inputs[0]
    assert_kind_of Puma::NullIO, @inputs[1]
  end

  def test_keepalive_doesnt_starve_clients
    sz = @body[0].size.to_s

    @client << @valid_request

    c2 = TCPSocket.new @host, @port
    c2 << @valid_request

    out = IO.select([c2], nil, nil, 1)

    assert out, "select returned nil"
    assert_equal c2, out.first.first

    assert_equal "HTTP/1.1 200 OK\r\nX-Header: Works\r\nContent-Length: #{sz}\r\n\r\n", lines(4, c2)
    assert_equal "Hello", c2.read(5)
  end

end
