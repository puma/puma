require_relative "helper"
require_relative "helpers/puma_socket"

class TestPersistent < Minitest::Test
  parallelize_me!
  include PumaTest::PumaSocket

  VALID_REQUEST  = "GET / HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\n\r\n"
  CLOSE_REQUEST  = "GET / HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n"
  HTTP10_REQUEST = "GET / HTTP/1.0\r\nHost: test.com\r\nContent-Type: text/plain\r\n\r\n"
  KEEP_REQUEST   = "GET / HTTP/1.0\r\nHost: test.com\r\nContent-Type: text/plain\r\nConnection: Keep-Alive\r\n\r\n"

  VALID_POST     = "POST / HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nhello"
  VALID_NO_BODY  = "GET / HTTP/1.1\r\nHost: test.com\r\nX-Status: 204\r\nContent-Type: text/plain\r\n\r\n"

  def setup
    @headers = { "X-Header" => "Works" }
    @body = ["Hello"]
    @cl = @body[0].bytesize

    app = ->(env) do
      status = Integer(env['HTTP_X_STATUS'] || 200)
      [status, @headers, @body]
    end

    opts = {min_threads: 1, max_threads: 1}
    @server = Puma::Server.new app, nil, opts
    @port = (@server.add_tcp_listener HOST, 0).addr[1]
    @server.run
    sleep 0.1 until @server.running == opts[:min_threads]
    @client = new_connection
  end

  def teardown
    @server.stop(true)
  end

  def test_one_with_content_length
    @client << VALID_REQUEST

    expected = "HTTP/1.1 200 OK\r\nX-Header: Works\r\nContent-Length: #{@cl}\r\n\r\n#{@body[0]}"

    assert_equal expected, @client.read_response
  end

  def test_two_back_to_back
    expected = "HTTP/1.1 200 OK\r\nX-Header: Works\r\nContent-Length: #{@cl}\r\n\r\n#{@body[0]}"

    @client << VALID_REQUEST

    assert_equal expected, @client.read_response

    @client << VALID_REQUEST

    assert_equal expected, @client.read_response
  end

  def test_post_then_get
    expected = "HTTP/1.1 200 OK\r\nX-Header: Works\r\nContent-Length: #{@cl}\r\n\r\n#{@body[0]}"

    @client << VALID_POST
    assert_equal expected, @client.read_response

    @client << VALID_REQUEST
    assert_equal expected, @client.read_response
  end

  def test_no_body_then_get
    @client << VALID_NO_BODY

    assert_equal "HTTP/1.1 204 No Content\r\nX-Header: Works\r\n\r\n", @client.read_response

    @client << VALID_REQUEST

    expected = "HTTP/1.1 200 OK\r\nX-Header: Works\r\nContent-Length: #{@cl}\r\n\r\n#{@body[0]}"

    assert_equal expected, @client.read_response
  end

  def test_chunked
    @body << "Chunked"
    @body = @body.to_enum

    @client << VALID_REQUEST

    expected = "HTTP/1.1 200 OK\r\nX-Header: Works\r\nTransfer-Encoding: chunked\r\n\r\n" \
      "5\r\nHello\r\n7\r\nChunked\r\n0\r\n\r\n"

    assert_equal expected, @client.read_response
  end

  def test_chunked_with_empty_part
    @body << ""
    @body << "Chunked"
    @body = @body.to_enum

    @client << VALID_REQUEST

    expected = "HTTP/1.1 200 OK\r\nX-Header: Works\r\nTransfer-Encoding: chunked\r\n\r\n" \
      "5\r\n#{@body.to_a[0]}\r\n7\r\nChunked\r\n0\r\n\r\n"

    assert_equal expected, @client.read_response
  end

  def test_no_chunked_in_http10
    @body << "Chunked"
    @body = @body.to_enum

    @client << HTTP10_REQUEST

    expected = "HTTP/1.0 200 OK\r\nX-Header: Works\r\n\r\nHelloChunked"

    # may only receive the first element ('Hello')
    Thread.pass if Puma::IS_JRUBY
    sleep 0.01

    assert_equal expected, @client.read_response
  end

  def test_hex
    str = "This is longer and will be in hex"
    @body << str
    @body = @body.to_enum

    @client << VALID_REQUEST

    expected = "HTTP/1.1 200 OK\r\nX-Header: Works\r\nTransfer-Encoding: chunked\r\n\r\n" \
      "5\r\nHello\r\n#{str.size.to_s(16)}\r\n#{str}\r\n0\r\n\r\n"

    assert_equal expected, @client.read_response
  end

  def test_client11_close
    @client << CLOSE_REQUEST

    expected = "HTTP/1.1 200 OK\r\nX-Header: Works\r\nConnection: close\r\nContent-Length: #{@cl}\r\n\r\n#{@body[0]}"

    assert_equal expected, @client.read_response
  end

  def test_client10_close
    @client << HTTP10_REQUEST

    expected = "HTTP/1.0 200 OK\r\nX-Header: Works\r\nContent-Length: #{@cl}\r\n\r\n#{@body[0]}"

    assert_equal expected, @client.read_response
  end

  def test_one_with_keep_alive_header
    @client << KEEP_REQUEST

    expected = "HTTP/1.0 200 OK\r\nX-Header: Works\r\nConnection: Keep-Alive\r\nContent-Length: #{@cl}\r\n\r\n#{@body[0]}"

    assert_equal expected, @client.read_response
  end

  def test_persistent_timeout
    @server.instance_variable_set(:@persistent_timeout, 1)
    @client << VALID_REQUEST

    expected = "HTTP/1.1 200 OK\r\nX-Header: Works\r\nContent-Length: #{@cl}\r\n\r\n#{@body[0]}"
    assert_equal expected, @client.read_response

    sleep 2

    assert_raises EOFError do
      @client.read_nonblock(1)
    end
  end

  def test_app_sets_content_length
    @body = ["hello", " world"]
    @headers['Content-Length'] = "11"

    @client << VALID_REQUEST

    expected = "HTTP/1.1 200 OK\r\nX-Header: Works\r\nContent-Length: 11\r\n\r\nhello world"

    assert_equal expected, @client.read_response
  end

  def test_allow_app_to_chunk_itself
    @headers = {'Transfer-Encoding' => "chunked" }

    @body = ["5\r\nhello\r\n0\r\n\r\n"]

    @client << VALID_REQUEST

    expected = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n"

    assert_equal expected, @client.read_response
  end


  def test_two_requests_in_one_chunk
    @server.instance_variable_set(:@persistent_timeout, 3)

    req = "#{VALID_REQUEST}GET /second HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\n\r\n"

    @client << req

    expected = "HTTP/1.1 200 OK\r\nX-Header: Works\r\nContent-Length: #{@cl}\r\n\r\n#{@body[0]}"

    assert_equal expected, @client.read_response(len: expected.bytesize)
    assert_equal expected, @client.read_response
  end

  def test_second_request_not_in_first_req_body
    @server.instance_variable_set(:@persistent_timeout, 3)

    req = "#{VALID_REQUEST}GET /second HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\n\r\n"

    @client << req

    expected = "HTTP/1.1 200 OK\r\nX-Header: Works\r\nContent-Length: #{@cl}\r\n\r\n#{@body[0]}"

    assert_equal expected, @client.read_response(len: expected.bytesize)
    assert_equal expected, @client.read_response
  end

  def test_keepalive_doesnt_starve_clients

    @client << VALID_REQUEST

    c2 = send_http VALID_REQUEST

    assert c2.wait_readable(1), "2nd request starved"

    expected = "HTTP/1.1 200 OK\r\nX-Header: Works\r\nContent-Length: #{@cl}\r\n\r\n#{@body[0]}"

    assert_equal expected, @client.read_response

    assert_equal expected, c2.read_response
  ensure
    c2.close
  end
end
