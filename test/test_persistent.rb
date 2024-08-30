# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/test_puma/puma_socket"

class TestPersistent < Minitest::Test
  parallelize_me!

  include ::TestPuma::PumaSocket

  HOST = "127.0.0.1"

  def setup
    @body = ["Hello"]

    @valid_request  = "GET / HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\n\r\n"

    @valid_response = <<~RESP.gsub("\n", "\r\n").rstrip
      HTTP/1.1 200 OK
      X-Header: Works
      Content-Length: 5

      Hello
    RESP

    @close_request  = "GET / HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n"
    @http10_request = "GET / HTTP/1.0\r\nHost: test.com\r\nContent-Type: text/plain\r\n\r\n"
    @keep_request   = "GET / HTTP/1.0\r\nHost: test.com\r\nContent-Type: text/plain\r\nConnection: Keep-Alive\r\n\r\n"

    @valid_post    = "POST / HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nhello"
    @valid_no_body  = "GET / HTTP/1.1\r\nHost: test.com\r\nX-Status: 204\r\nContent-Type: text/plain\r\n\r\n"

    @headers = { "X-Header" => "Works" }
    @inputs = []

    @simple = lambda do |env|
      @inputs << env['rack.input']
      status = Integer(env['HTTP_X_STATUS'] || 200)
      [status, @headers, @body]
    end

    opts = {min_thread: 1, max_threads: 1}
    @server = Puma::Server.new @simple, nil, opts
    @bind_port = (@server.add_tcp_listener HOST, 0).addr[1]
    @server.run
    sleep 0.15 if Puma.jruby?
  end

  def teardown
    @server.stop(true)
  end

  def test_one_with_content_length
    response = send_http_read_response @valid_request

    assert_equal @valid_response, response
  end

  def test_two_back_to_back
    socket = send_http @valid_request
    response = socket.read_response

    assert_equal @valid_response, response

    response = socket.req_write(@valid_request).read_response

    assert_equal @valid_response, response
  end

  def test_post_then_get
    socket = send_http @valid_post
    response = socket.read_response

    expected = <<~RESP.gsub("\n", "\r\n").rstrip
      HTTP/1.1 200 OK
      X-Header: Works
      Content-Length: 5

      Hello
    RESP

    assert_equal expected, response

    response = socket.req_write(@valid_request).read_response

    assert_equal @valid_response, response
  end

  def test_no_body_then_get
    socket = send_http @valid_no_body
    response = socket.read_response
    assert_equal "HTTP/1.1 204 No Content\r\nX-Header: Works\r\n\r\n", response

    response = socket.req_write(@valid_request).read_response

    assert_equal @valid_response, response
  end

  def test_chunked
    @body << "Chunked"
    @body = @body.to_enum

    response = send_http_read_response @valid_request

    assert_equal "HTTP/1.1 200 OK\r\nX-Header: Works\r\nTransfer-Encoding: chunked\r\n\r\n" \
      "5\r\nHello\r\n7\r\nChunked\r\n0\r\n\r\n", response
  end

  def test_chunked_with_empty_part
    @body << ""
    @body << "Chunked"
    @body = @body.to_enum

    response = send_http_read_response @valid_request

    assert_equal "HTTP/1.1 200 OK\r\nX-Header: Works\r\nTransfer-Encoding: chunked\r\n\r\n" \
      "5\r\nHello\r\n7\r\nChunked\r\n0\r\n\r\n", response
  end

  def test_no_chunked_in_http10
    @body << "Chunked"
    @body = @body.to_enum

    response = send_http_read_response GET_10

    assert_equal "HTTP/1.0 200 OK\r\nX-Header: Works\r\n\r\n" \
      "HelloChunked", response
  end

  def test_hex
    str = "This is longer and will be in hex"
    @body << str
    @body = @body.to_enum

    response = send_http_read_response @valid_request

    assert_equal "HTTP/1.1 200 OK\r\nX-Header: Works\r\nTransfer-Encoding: chunked\r\n\r\n" \
      "5\r\nHello\r\n#{str.size.to_s(16)}\r\n#{str}\r\n0\r\n\r\n", response
  end

  def test_client11_close
    response = send_http_read_response @close_request

    assert_equal "HTTP/1.1 200 OK\r\nX-Header: Works\r\nConnection: close\r\nContent-Length: 5\r\n\r\n" \
      "Hello", response
  end

  def test_client10_close
    response = send_http_read_response GET_10

    assert_equal "HTTP/1.0 200 OK\r\nX-Header: Works\r\nContent-Length: 5\r\n\r\n" \
      "Hello", response
  end

  def test_one_with_keep_alive_header
    response = send_http_read_response @keep_request

    assert_equal "HTTP/1.0 200 OK\r\nX-Header: Works\r\nConnection: Keep-Alive\r\nContent-Length: 5\r\n\r\n" \
      "Hello", response
  end

  def test_persistent_timeout
    @server.instance_variable_set(:@persistent_timeout, 1)

    socket = send_http @valid_request
    response = socket.read_response

    assert_equal "HTTP/1.1 200 OK\r\nX-Header: Works\r\nContent-Length: 5\r\n\r\n" \
      "Hello", response

    sleep 2

    assert_raises EOFError do
      socket.read_nonblock(1)
    end
  end

  def test_app_sets_content_length
    @body = ["hello", " world"]
    @headers['Content-Length'] = "11"

    response = send_http_read_response @valid_request

    assert_equal "HTTP/1.1 200 OK\r\nX-Header: Works\r\nContent-Length: 11\r\n\r\n" \
      "hello world", response
  end

  def test_allow_app_to_chunk_itself
    @headers = {'Transfer-Encoding' => "chunked" }

    @body = ["5\r\nhello\r\n0\r\n\r\n"]

    response = send_http_read_response @valid_request

    assert_equal "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n" \
      "5\r\nhello\r\n0\r\n\r\n", response
  end

  def test_two_requests_in_one_chunk
    @server.instance_variable_set(:@persistent_timeout, 3)

    req = @valid_request.to_s
    req += "GET /second HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\n\r\n"

    response = send_http_read_all req

    assert_equal @valid_response * 2, response
  end

  def test_second_request_not_in_first_req_body
    @server.instance_variable_set(:@persistent_timeout, 3)

    req = @valid_request.to_s
    req += "GET /second HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\n\r\n"

    response = send_http_read_all req

    assert_equal @valid_response * 2, response

    assert_kind_of Puma::NullIO, @inputs[0]
    assert_kind_of Puma::NullIO, @inputs[1]
  end

  def test_keepalive_doesnt_starve_clients
    sz = @body[0].size.to_s

    send_http @valid_request

    c2 = send_http @valid_request

    assert c2.wait_readable(1), "2nd request starved"

    response = c2.read_response

    assert_equal "HTTP/1.1 200 OK\r\nX-Header: Works\r\nContent-Length: 5\r\n\r\n" \
      "Hello", response
  end
end
