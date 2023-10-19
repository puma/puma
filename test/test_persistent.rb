# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/test_puma/server_in_process"

class TestPersistent < TestPuma::ServerInProcess
  parallelize_me!

  VALID_REQUEST     = "GET / HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\n\r\n"
  CLOSE_REQUEST     = "GET / HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n"
  HTTP10_REQUEST    = "GET / HTTP/1.0\r\nHost: test.com\r\nContent-Type: text/plain\r\n\r\n"
  HTTP10_KA_REQUEST = "GET / HTTP/1.0\r\nHost: test.com\r\nContent-Type: text/plain\r\nConnection: Keep-Alive\r\n\r\n"

  VALID_POST    = "POST / HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nhello"
  VALID_NO_BODY  = "GET / HTTP/1.1\r\nHost: test.com\r\nX-Status: 204\r\nContent-Type: text/plain\r\n\r\n"

  HTTP11_200_OK = "HTTP/1.1 200 OK"

  def setup
    @headers = { "X-Header" => "Works" }
    @body = ["Hello"]
    @size = @body[0].size.to_s

    @inputs = []

    @simple = ->(env) do
      @inputs << env['rack.input']
      status = Integer(env['HTTP_X_STATUS'] || 200)
      [status, @headers, @body]
    end

    server_run app: @simple
  end

  def assert_response(response, status = HTTP11_200_OK)
    standard_response = @standard_response = <<~RESP.gsub("\n", "\r\n").strip
      #{status}
      X-Header: Works
      Content-Length: #{@size}

      Hello
    RESP
    assert_equal standard_response, response

    assert_equal status, response.status
    assert_equal ["X-Header: Works", "Content-Length: #{@size}"], response.headers
    assert_equal "Hello", response.body
  end

  def test_one_with_content_length
    assert_response send_http_read_response(VALID_REQUEST)
  end

  def test_two_back_to_back
    socket = send_http VALID_REQUEST

    assert_response socket.read_response

    assert_response socket.send_request(VALID_REQUEST).read_response
  end

  def test_post_then_get
    socket = send_http VALID_POST

    assert_response socket.read_response

    assert_response socket.send_request(VALID_REQUEST).read_response
  end

  def test_no_body_then_get
    socket = send_http VALID_NO_BODY
    assert_equal "HTTP/1.1 204 No Content\r\nX-Header: Works\r\n\r\n",
      socket.read_response

    assert_response socket.send_request(VALID_REQUEST).read_response
  end

  def test_chunked
    @body << "Chunked"
    @body = @body.to_enum

    response = send_http_read_response VALID_REQUEST

    assert_equal HTTP11_200_OK, response.status
    assert_equal ["X-Header: Works", "Transfer-Encoding: chunked"], response.headers
    assert_equal "5\r\nHello\r\n7\r\nChunked\r\n0\r\n\r\n", response.body
    assert_equal "HelloChunked", response.decode_body
  end

  def test_chunked_with_empty_part
    @body << ""
    @body << "Chunked"
    @body = @body.to_enum

    response = send_http_read_response VALID_REQUEST

    assert_equal HTTP11_200_OK, response.status
    assert_equal ["X-Header: Works", "Transfer-Encoding: chunked"], response.headers
    assert_equal "5\r\nHello\r\n7\r\nChunked\r\n0\r\n\r\n", response.body
    assert_equal "HelloChunked", response.decode_body
  end

  def test_no_chunked_in_http10
    @body << "Chunked"
    @body = @body.to_enum

    socket = send_http HTTP10_REQUEST
    sleep 0.01 if Puma::IS_JRUBY # may just receive 'Hello'
    response = socket.read_response

    assert_equal "HTTP/1.0 200 OK", response.status
    assert_equal ["X-Header: Works"], response.headers
    assert_equal "HelloChunked", response.body
  end

  def test_hex
    str = "This is longer and will be in hex"
    @body << str
    @body = @body.to_enum

    response = send_http_read_response VALID_REQUEST

    assert_equal HTTP11_200_OK, response.status
    assert_equal ["X-Header: Works", "Transfer-Encoding: chunked"], response.headers
    assert_equal "5\r\nHello\r\n#{str.size.to_s(16)}\r\n#{str}\r\n0\r\n\r\n", response.body
    assert_equal "HelloThis is longer and will be in hex", response.decode_body
  end

  def test_client11_close
    response = send_http_read_response CLOSE_REQUEST

    assert_equal HTTP11_200_OK, response.status
    assert_equal ["X-Header: Works", "Connection: close", "Content-Length: #{@size}"],
      response.headers
    assert_equal "Hello", response.body
  end

  def test_client10_close
    response = send_http_read_response HTTP10_REQUEST

    assert_response(response, "HTTP/1.0 200 OK")
  end

  def test_one_with_keep_alive_header
    response = send_http_read_response HTTP10_KA_REQUEST

    assert_equal "HTTP/1.0 200 OK", response.status
    assert_equal ["X-Header: Works", "Connection: Keep-Alive", "Content-Length: #{@size}"],
      response.headers
    assert_equal "Hello", response.body
  end

  def test_persistent_timeout
    @server.instance_variable_set(:@persistent_timeout, 1)
    socket = send_http VALID_REQUEST
    assert_response(socket.read_response)

    sleep 1.5

    assert_raises EOFError do
      socket.read_nonblock 1
    end
  end

  def test_app_sets_content_length
    @body = ["hello", " world"]
    @headers['Content-Length'] = "11"

    response = send_http_read_response VALID_REQUEST

    assert_equal HTTP11_200_OK, response.status
    assert_equal ["X-Header: Works", "Content-Length: 11"], response.headers
    assert_equal "hello world", response.body
  end

  def test_allow_app_to_chunk_itself
    @headers = {'Transfer-Encoding' => "chunked" }

    @body = ["5\r\nhello\r\n0\r\n\r\n"]

    response = send_http_read_response VALID_REQUEST

    assert_equal HTTP11_200_OK, response.status
    assert_equal ["Transfer-Encoding: chunked"], response.headers
    assert_equal "5\r\nhello\r\n0\r\n\r\n", response.body
    assert_equal "hello", response.decode_body
  end

  def test_two_requests_in_one_chunk
    @server.instance_variable_set(:@persistent_timeout, 3)

    req = VALID_REQUEST.to_s
    req += "GET /second HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\n\r\n"

    data = send_http_read_all req

    first_resp, remaining = data.split "\r\n\r\n", 2
    first_resp << "\r\n\r\n" << remaining[0, 5]
    second_resp = remaining[5..-1]

    assert_response TestPuma::Response.new(first_resp)
    assert_response TestPuma::Response.new(second_resp)
  end

  def test_second_request_not_in_first_req_body
    @server.instance_variable_set(:@persistent_timeout, 3)

    req = VALID_REQUEST.to_s
    req += "GET /second HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\n\r\n"

    data = send_http_read_all req

    first_resp, remaining = data.split "\r\n\r\n", 2
    first_resp << "\r\n\r\n" << remaining[0, 5]
    second_resp = remaining[5..-1]

    assert_response TestPuma::Response.new(first_resp)
    assert_response TestPuma::Response.new(second_resp)

    assert_kind_of Puma::NullIO, @inputs[0]
    assert_kind_of Puma::NullIO, @inputs[1]
  end

  def test_keepalive_doesnt_starve_clients
    socket1 = send_http VALID_REQUEST
    socket2 = send_http VALID_REQUEST

    assert socket2.wait_readable(1), "2nd request starved"

    assert_response socket1.read_response
    assert_response socket2.read_response
  end
end
