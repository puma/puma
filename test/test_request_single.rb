# frozen_string_literal: true

require_relative "helper"

require 'puma/client'

# this file tests both valid and invalid requests using only `Puma::Client'.
# It cannot test behavior with multiple requests, for that, see
# `test_request_invalid_multiple.rb`

class TestRequestBase < PumaTest

  include Puma::Const

  PEER_ADDR = -> () { ["AF_INET", 80, "127.0.0.1", "127.0.0.1"] }

  GET_PREFIX = "GET / HTTP/1.1\r\nConnection: close\r\n"
  CHUNKED = "1\r\nH\r\n4\r\nello\r\n5\r\nWorld\r\n0\r\n\r\n"

  HTTP_METHODS = SUPPORTED_HTTP_METHODS.sort.product([nil]).to_h.freeze

  USE_IO_PIPE = Puma::IS_OSX && (RUBY_VERSION < '3.0' || !Puma::IS_MRI)

  def create_client(request, &blk)
    env = {}
    if Puma::IS_WINDOWS
      @rd, @wr = Socket.pair Socket::AF_INET, Socket::SOCK_STREAM, 0
    elsif USE_IO_PIPE
      @rd, @wr = IO.pipe
    else
      @rd, @wr = UNIXSocket.pair
    end

    @rd.define_singleton_method :peeraddr, PEER_ADDR

    @client = Puma::Client.new @rd, env
    @client.supported_http_methods = HTTP_METHODS
    @parser = @client.instance_variable_get :@parser

    yield @client if blk

    written = 0
    i_limit = 64 * 1024
    size = request.bytesize
    while written < size
      written += @wr.syswrite(request.byteslice written, i_limit)
      @wr&.close if written == size
      break if @client.try_to_finish
    end
  end

  def assert_invalid(req, msg, err: Puma::HttpParserError, status: nil, start_with: false, &blk)
    error = assert_raises(err) { create_client req, &blk }

    if start_with
      assert_start_with error.message, msg
    else
      assert_equal msg, error.message
    end
    assert_equal 'close', @client.env[HTTP_CONNECTION],
      "env['HTTP_CONNECTION'] should be set to 'close'"
    if status
      assert_equal(status, @client.error_status_code)
      if status == 413
        assert @client.http_content_length_limit_exceeded
      end
    end
  end

  def teardown
    @wr&.close
    @rd&.close
    @parser = nil
    @client = nil
  end
end

# Tests request start line, which sets `env` values for:
#
# * HTTP_CONNECTION
# * QUERY_STRING
# * REQUEST_METHOD
# * REQUEST_PATH
# * REQUEST_URI
# * SERVER_PROTOCOL
#
class TestRequestLineValid < TestRequestBase

  def test_method
    create_client "GET /?a=1 HTTP/1.1\r\n\r\n"

    assert_equal 'GET', @client.env[REQUEST_METHOD]
  end

  def test_path_plain
    create_client "GET /puma/request HTTP/1.1\r\n\r\n"

    assert_equal '/puma/request', @client.env[REQUEST_PATH]
  end

  def test_path_with_query
    create_client "GET /puma/request?query=books&sort=price&order=asc HTTP/1.1\r\n\r\n"

    assert_equal '/puma/request', @client.env[REQUEST_PATH]
  end

  def test_query
    create_client "GET /puma/request?query=books&sort=price&order=asc HTTP/1.1\r\n\r\n"

    assert_equal 'query=books&sort=price&order=asc', @client.env[QUERY_STRING]
  end

  def test_uri
    create_client "GET /puma/request?query=books&sort=price&order=asc HTTP/1.1\r\n\r\n"

    assert_equal '/puma/request?query=books&sort=price&order=asc', @client.env[REQUEST_URI]
  end

  def test_PROTOCOL_1_0
    create_client "GET /puma/request?query=books&sort=price&order=asc HTTP/1.0\r\n\r\n"

    assert_equal 'HTTP/1.0', @client.env[SERVER_PROTOCOL]
  end

  def test_PROTOCOL_1_1
    create_client "GET /puma/request?query=books&sort=price&order=asc HTTP/1.1\r\n\r\n"

    assert_equal 'HTTP/1.1', @client.env[SERVER_PROTOCOL]
  end

  def test_gzip_chunked
    te = "gzip \t , \t chunked"
    request = <<~REQ.gsub("\n", "\r\n").rstrip
      GET / HTTP/1.1
      Transfer_Encoding: #{te}
      Content_Length: 11

      Hello World
    REQ

    create_client request

    if @parser.finished?
      assert_equal '11', @client.env['HTTP_CONTENT,LENGTH']
      assert_equal te, @client.env['HTTP_TRANSFER,ENCODING']
      assert_instance_of Puma::NullIO, @client.body
    else
      fail
    end
  end
end

# Tests request start line, which sets `env` values for:
#
# * HTTP_CONNECTION
# * QUERY_STRING
# * REQUEST_METHOD
# * REQUEST_PATH
# * REQUEST_URI
# * SERVER_PROTOCOL
#
class TestRequestLineInvalid < TestRequestBase

  # An ssl request will probably be scrambled
  def test_maybe_ssl
    assert_invalid "a_}{n",
      "Invalid HTTP format, parsing fails. Are you trying to open an SSL connection to a non-SSL Puma?"
  end

  def test_method_lower_case
    assert_invalid "GEt /?a=1 HTTP/1.1\r\n\r\n",
      "Invalid HTTP format, parsing fails. Bad method GEt"
  end

  def test_method_non_standard
    assert_invalid "PUMA /?a=1 HTTP/1.1\r\n\r\n",
      "PUMA method is not supported",
      err: Puma::HttpParserError501
  end

  def test_method_user_not_allowed
    assert_invalid("POST /?a=1 HTTP/1.1\r\n\r\n",
      "POST method is not supported",
      err: Puma::HttpParserError501) { |c| c.supported_http_methods =
        {'HEAD' => nil, 'GET' => nil}
      }
  end

  def test_path_non_printable
    assert_invalid "GET /\e?a=1 HTTP/1.1\r\n\r\n",
      "Invalid HTTP format, parsing fails. Bad path /\e"
  end

  def test_query_non_printable
    assert_invalid "GET /?a=\e1 HTTP/1.1\r\n\r\n",
      "Invalid HTTP format, parsing fails. Bad query a=\e1"
  end

  def test_protocol_prefix_lower_case
    assert_invalid "GET /test?a=1 http/1.1\r\n\r\n",
      "Invalid HTTP format, parsing fails. Bad protocol http/1.1"
  end

  def test_protocol_suffix
    assert_invalid "GET /test?a=1 HTTP/1.a\r\n\r\n",
      "Invalid HTTP format, parsing fails. Bad protocol HTTP/1.a"
  end
end

# Tests limits set in `ext/puma_http11/puma_http11.c`
class TestRequestOversizeItem < TestRequestBase

  # limit is 256
  def test_header_name
    request = "GET /test1 HTTP/1.1\r\n#{'a' * 257}: val\r\n\r\n"

    msg = Puma::IS_JRUBY ?
      "HTTP element FIELD_NAME is longer than the 256 allowed length." :
      "HTTP element FIELD_NAME is longer than the 256 allowed length (was 257)"

    assert_invalid request, msg
  end

  # limit is 80 * 1024
  def test_header_value
    request = "GET /test1 HTTP/1.1\r\ntest: #{'a' * (80 * 1_024 + 1)}\r\n\r\n"

    msg = Puma::IS_JRUBY ?
      "HTTP element FIELD_VALUE is longer than the 81920 allowed length." :
      "HTTP element FIELD_VALUE is longer than the 80 * 1024 allowed length (was 81921)"

    assert_invalid request, msg
  end

  # limit is 1024
  def test_request_fragment
    request = "GET /##{'a' * 1025} HTTP/1.1\r\n\r\n"

    msg = Puma::IS_JRUBY ?
      "HTTP element FRAGMENT is longer than the 1024 allowed length." :
      "HTTP element FRAGMENT is longer than the 1024 allowed length (was 1025)"

    assert_invalid request, msg
  end

  # limit is (80 + 32) * 1024
  def test_headers
    hdrs = "#{'a' * 256}: #{'a' * (2048 - 256)}\r\n" * 56

    msg = Puma::IS_JRUBY ?
      "HTTP element HEADER is longer than the 114688 allowed length." :
      "HTTP element HEADER is longer than the (1024 * (80 + 32)) allowed length ("

    assert_invalid "GET / HTTP/1.1\r\n#{hdrs}\r\n", msg, start_with: true
  end

  # limit is 10 * 1024
  def test_query_string
    request = "GET /?#{'a' * (5 * 1024)}=#{'b' * (5 * 1024)} HTTP/1.1\r\n\r\n"

    msg = Puma::IS_JRUBY ?
      "HTTP element QUERY_STRING is longer than the 10240 allowed length." :
      "HTTP element QUERY_STRING is longer than the (1024 * 10) allowed length (was 10241)"

    assert_invalid request, msg
  end

  # limit is 8 * 1024
  def test_request_path
    msg = Puma::IS_JRUBY ?
      "HTTP element REQUEST_PATH is longer than the 8192 allowed length." :
      "HTTP element REQUEST_PATH is longer than the (8192) allowed length (was 8193)"

    assert_invalid "GET /#{'a' * (8 * 1024)} HTTP/1.1\r\n\r\n", msg
  end

  # limit is 12 * 1024
  def test_request_uri
    request = "GET /#{'a' * 6 * 1024}?#{'a' * 3 * 1024}=#{'a' * 3 * 1024} HTTP/1.1\r\n\r\n"

    msg = Puma::IS_JRUBY ?
      "HTTP element REQUEST_URI is longer than the 12288 allowed length." :
      "HTTP element REQUEST_URI is longer than the (1024 * 12) allowed length (was 12291)"

    assert_invalid request, msg
  end

  def test_content_length_exceeded
    long_string = 'a' * 200_000

    request = "GET / HTTP/1.1\r\nConnection: Keep-Alive\r\nContent-Length: 200000\r\n\r\n" \
      "#{long_string}"

    msg = 'Payload Too Large'

    assert_invalid(request, msg, status: 413) { |client| client.http_content_length_limit = 65 * 1_024 }
  end

  def test_content_length_exceeded_chunked
    chunk_length = 20_000
    chunk_part_qty = 10

    long_string = 'a' * chunk_length
    long_string_part = "#{long_string.bytesize.to_s 16}\r\n#{long_string}\r\n"
    long_chunked = "#{long_string_part * chunk_part_qty}0\r\n\r\n"

    request = "GET / HTTP/1.1\r\nConnection: Keep-Alive\r\n" \
      "Transfer-Encoding: chunked\r\n\r\n#{long_chunked}"

    msg = 'Payload Too Large'

    assert_invalid(request, msg, status: 413) { |client| client.http_content_length_limit = 65 * 1_024 }
  end
end

# Tests requests that require special handling of headers
class TestRequestHeadersValid < TestRequestBase

  def test_content
    create_client "GET / HTTP/1.1\r\nContent-Length: 11\r\n\r\nHello World"

    assert_instance_of Float, @client.env['puma.request_body_wait']
    assert_equal '11', @client.env[CONTENT_LENGTH]
    assert_equal 'Hello World', @client.env['rack.input'].read
  end

  def test_content_chunked
    request = request = <<~REQ.gsub("\n", "\r\n")
      GET / HTTP/1.1
      Transfer-Encoding: chunked

      11
      Transfer-Encoding
      9
      Puma Test
      11
      Transfer-Encoding
      0

    REQ

    create_client request

    assert_instance_of Float, @client.env['puma.request_body_wait']
    refute_operator @client.env, :key?, TRANSFER_ENCODING2
    assert_equal '43', @client.env[CONTENT_LENGTH]
    assert_equal 'Transfer-EncodingPuma TestTransfer-Encoding', @client.env['rack.input'].read
  end

  # if a header with an underscore exists, and is a singular key,  accept it
  def test_underscore_single
    request = "GET / HTTP/1.1\r\n" \
      "x_forwarded_for: 1.1.1.1\r\n" \
      "Content-Length: 11\r\n\r\nHello World"

    create_client request

    assert_equal "1.1.1.1", @client.env['HTTP_X_FORWARDED_FOR']
  end

  def test_underscore_header_1
    request = <<~REQ.gsub("\n", "\r\n").rstrip
      GET / HTTP/1.1
      x-forwarded_for: 2.2.2.2
      x-forwarded-for: 1.1.1.1
      Content-Length: 11

      Hello World
    REQ

    create_client request

    assert_equal "1.1.1.1", @client.env['HTTP_X_FORWARDED_FOR']
    assert_equal "Hello World", @client.body.string
  end

  def test_underscore_header_2
    hdrs = [
      "X-FORWARDED-FOR: 1.1.1.1",  # proper
      "X-FORWARDED-FOR: 2.2.2.2",  # proper
      "X_FORWARDED-FOR: 3.3.3.3",  # invalid, contains underscore
      "Content-Length: 5",
    ].join "\r\n"

    create_client "#{GET_PREFIX}#{hdrs}\r\n\r\nHello\r\n\r\n"

    assert_equal "1.1.1.1, 2.2.2.2", @client.env['HTTP_X_FORWARDED_FOR']
    assert_equal "Hello", @client.body.string
  end

  def test_underscore_header_3
    hdrs = [
      "X_FORWARDED-FOR: 3.3.3.3",  # invalid, contains underscore
      "X-FORWARDED-FOR: 2.2.2.2",  # proper
      "X-FORWARDED-FOR: 1.1.1.1",  # proper
      "Content-Length: 5",
    ].join "\r\n"

    create_client "#{GET_PREFIX}#{hdrs}\r\n\r\nHello\r\n\r\n"

    assert_equal "2.2.2.2, 1.1.1.1", @client.env['HTTP_X_FORWARDED_FOR']
    assert_equal "Hello", @client.body.string
  end

  def test_unmaskable_headers
    request = <<~REQ.gsub("\n", "\r\n").rstrip
      GET / HTTP/1.1
      Transfer_Encoding: chunked
      Content_Length: 11

      Hello World
    REQ

    create_client request

    assert_equal '11', @client.env['HTTP_CONTENT,LENGTH']
    assert_equal 'chunked', @client.env['HTTP_TRANSFER,ENCODING']
    assert_instance_of Puma::NullIO, @client.body
  end

  def test_default_port
    request = <<~REQ.gsub("\n", "\r\n")
      GET / HTTP/1.0
      Host: example.com

    REQ

    create_client request

    assert_equal 'example.com', @client.env[SERVER_NAME]
    assert_equal '80', @client.env[SERVER_PORT]
    assert_instance_of Puma::NullIO, @client.body
  end

  def test_hostname_and_port
    request = <<~REQ.gsub("\n", "\r\n")
      GET / HTTP/1.0
      Host: example.com:456

    REQ

    create_client request

    assert_equal 'example.com', @client.env[SERVER_NAME]
    assert_equal '456', @client.env[SERVER_PORT]
    assert_instance_of Puma::NullIO, @client.body
  end

  def test_host_header_missing
    create_client "GET / HTTP/1.0\r\n\r\n"

    assert_equal 'localhost', @client.env[SERVER_NAME]
    assert_equal '80', @client.env[SERVER_PORT]
  end

  def test_host_ipv4_port
    request = <<~REQ.gsub("\n", "\r\n")
      GET / HTTP/1.0
      Host: 123.123.123.123:456

    REQ

    create_client request

    assert_equal '123.123.123.123', @client.env[SERVER_NAME]
    assert_equal '456', @client.env[SERVER_PORT]
    assert_instance_of Puma::NullIO, @client.body
  end

  def test_ipv6_port
    request = <<~REQ.gsub("\n", "\r\n")
      GET / HTTP/1.0
      Host: [::ffff:127.0.0.1]:9292

    REQ

    create_client request

    assert_equal '[::ffff:127.0.0.1]', @client.env[SERVER_NAME]
    assert_equal '9292', @client.env[SERVER_PORT]
    assert_instance_of Puma::NullIO, @client.body
  end

  def test_respect_x_forwarded_proto
    request = <<~REQ.gsub("\n", "\r\n")
      GET / HTTP/1.0
      host: example.com
      x-forwarded-proto: https,http

    REQ

    create_client request

    assert_equal '443'   , @client.default_server_port
    assert_equal '443'   , @client.env[SERVER_PORT]
    assert_equal 'https' , @client.env[RACK_URL_SCHEME]
    assert_instance_of Puma::NullIO, @client.body
  end

  def test_respect_x_forwarded_ssl_on
    request = <<~REQ.gsub("\n", "\r\n")
      GET / HTTP/1.0
      host: example.com
      x-forwarded-ssl: on

    REQ

    create_client request

    assert_equal '443'   , @client.default_server_port
    assert_equal '443'   , @client.env[SERVER_PORT]
    assert_equal 'https' , @client.env[RACK_URL_SCHEME]
    assert_instance_of Puma::NullIO, @client.body
  end

  def test_respect_x_forwarded_scheme
    request = <<~REQ.gsub("\n", "\r\n")
      GET / HTTP/1.0
      host: example.com
      x-forwarded-scheme: https

    REQ

    create_client request

    assert_equal '443'   , @client.default_server_port
    assert_equal '443'   , @client.env[SERVER_PORT]
    assert_equal 'https' , @client.env[RACK_URL_SCHEME]
    assert_instance_of Puma::NullIO, @client.body
  end
end

# Tests the headers section of the request
class TestRequestHeadersInvalid < TestRequestBase

  def test_malformed_headers_no_return
    request = "GET / HTTP/1.1\r\nno-return: 10\nContent-Length: 11\r\n\r\nHello World"

    msg = Puma::IS_JRUBY ?
      "Invalid HTTP format, parsing fails. Bad headers\nno-return: 10\\nContent-Length: 11" :
      "Invalid HTTP format, parsing fails. Bad headers\nNO_RETURN: 10\\nContent-Length: 11"

    assert_invalid request, msg
  end

  def test_malformed_headers_no_newline
    request = "GET / HTTP/1.1\r\nno-newline: 10\rContent-Length: 11\r\n\r\nHello World"

    msg = Puma::IS_JRUBY ?
      "Invalid HTTP format, parsing fails. Bad headers\nno-newline: 10\rContent-Length: 11" :
      "Invalid HTTP format, parsing fails. Bad headers\nNO_NEWLINE: 10\rContent-Length: 11"

    assert_invalid request, msg
  end
end

# Tests requests with invalid Content-Length header
class TestRequestContentLengthInvalid < TestRequestBase

  def test_multiple
    cl = [
      'Content-Length: 5',
      'Content-Length: 5'
    ].join "\r\n"

    assert_invalid "#{GET_PREFIX}#{cl}\r\n\r\nHello\r\n\r\n",
      'Invalid Content-Length: "5, 5"', status: 400
  end

  def test_bad_characters_1
    cl = 'Content-Length: 5.01'

    assert_invalid "#{GET_PREFIX}#{cl}\r\n\r\nHello\r\n\r\n",
     'Invalid Content-Length: "5.01"', status: 400
  end

  def test_bad_characters_2
    cl = 'Content-Length: +5'

    assert_invalid "#{GET_PREFIX}#{cl}\r\n\r\nHello\r\n\r\n",
      'Invalid Content-Length: "+5"', status: 400
  end

  def test_bad_characters_3
    cl = 'Content-Length: 5 test'

    assert_invalid "#{GET_PREFIX}#{cl}\r\n\r\nHello\r\n\r\n",
    'Invalid Content-Length: "5 test"', status: 400
  end
end

# Tests invalid chunked requests
class TestRequestChunkedInvalid < TestRequestBase

  def test_chunked_size_bad_characters_1
    te = 'Transfer-Encoding: chunked'
    chunked ='5.01'

    assert_invalid "#{GET_PREFIX}#{te}\r\n\r\n" \
      "1\r\nh\r\n#{chunked}\r\nHello\r\n0\r\n\r\n",
      "Invalid chunk size: '5.01'"
  end

  def test_chunked_size_bad_characters_2
    te = 'Transfer-Encoding: chunked'
    chunked ='+5'

    assert_invalid "#{GET_PREFIX}#{te}\r\n\r\n" \
      "1\r\nh\r\n#{chunked}\r\nHello\r\n0\r\n\r\n",
      "Invalid chunk size: '+5'"
  end

  def test_chunked_size_bad_characters_3
    te = 'Transfer-Encoding: chunked'
    chunked ='5 bad'

    assert_invalid "#{GET_PREFIX}#{te}\r\n\r\n" \
      "1\r\nh\r\n#{chunked}\r\nHello\r\n0\r\n\r\n",
      "Invalid chunk size: '5 bad'"
  end

  def test_chunked_size_bad_characters_4
    te = 'Transfer-Encoding: chunked'
    chunked ='0xA'

    assert_invalid "#{GET_PREFIX}#{te}\r\n\r\n" \
      "1\r\nh\r\n#{chunked}\r\nHelloHello\r\n0\r\n\r\n",
      "Invalid chunk size: '0xA'"
  end

  # size is less than bytesize, 4 < 'world'.bytesize
  def test_chunked_size_mismatch_1
    te = 'Transfer-Encoding: chunked'
    chunked =
      "5\r\nHello\r\n" \
      "4\r\nWorld\r\n" \
      "0\r\n\r\n"

    assert_invalid "#{GET_PREFIX}#{te}\r\n\r\n#{chunked}",
      "Chunk size mismatch"
  end

  # size is greater than bytesize, 6 > 'world'.bytesize
  def test_chunked_size_mismatch_2
    te = 'Transfer-Encoding: chunked'
    chunked =
      "5\r\nHello\r\n" \
      "6\r\nWorld\r\n" \
      "0\r\n\r\n"

    assert_invalid "#{GET_PREFIX}#{te}\r\n\r\n#{chunked}",
      "Chunk size mismatch"
  end
end

# Tests invalid Transfer-Ecoding headers
class TestTransferEncodingInvalid < TestRequestBase

  def test_chunked_not_last
    te = [
      'Transfer-Encoding: chunked',
      'Transfer-Encoding: gzip'
    ].join "\r\n"

    assert_invalid "#{GET_PREFIX}#{te}\r\n\r\n#{CHUNKED}",
      "Invalid Transfer-Encoding, last value must be chunked: 'chunked, gzip'"
  end

  def test_chunked_multiple
    te = [
      'Transfer-Encoding: chunked',
      'Transfer-Encoding: gzip',
      'Transfer-Encoding: chunked'
    ].join "\r\n"

    assert_invalid "#{GET_PREFIX}#{te}\r\n\r\n#{CHUNKED}",
      "Invalid Transfer-Encoding, multiple chunked: 'chunked, gzip, chunked'"
  end

  def test_invalid_single
    te = 'Transfer-Encoding: xchunked'

    assert_invalid "#{GET_PREFIX}#{te}\r\n\r\n#{CHUNKED}",
      "Invalid Transfer-Encoding, unknown value: 'xchunked'",
      err: Puma::HttpParserError501
  end

  def test_invalid_multiple
    te = [
      'Transfer-Encoding: x_gzip',
      'Transfer-Encoding: gzip',
      'Transfer-Encoding: chunked'
    ].join "\r\n"

    assert_invalid "#{GET_PREFIX}#{te}\r\n\r\n#{CHUNKED}",
      "Invalid Transfer-Encoding, unknown value: 'x_gzip, gzip, chunked'",
      err: Puma::HttpParserError501
  end

  def test_single_not_chunked
    te = 'Transfer-Encoding: gzip'

    assert_invalid "#{GET_PREFIX}#{te}\r\n\r\n#{CHUNKED}",
      "Invalid Transfer-Encoding, single value must be chunked: 'gzip'"
  end
end

# Tests reset clears per-request error state
class TestRequestReset < TestRequestBase

  def test_reset_clears_error_status_code
    setup_client
    @client.http_content_length_limit = 10

    first_request = "GET / HTTP/1.1\r\nConnection: Keep-Alive\r\n\r\n"
    second_request = "GET /next HTTP/1.1\r\n\r\n"

    write_request "#{first_request}#{second_request}"

    assert_equal '/', @client.env[REQUEST_PATH]
    assert_nil @client.error_status_code

    @client.reset

    assert @client.process_back_to_back_requests
    assert_equal '/next', @client.env[REQUEST_PATH]
    assert_nil @client.error_status_code
  end

  private

  def setup_client
    env = {}
    if Puma::IS_WINDOWS
      @rd, @wr = Socket.pair Socket::AF_INET, Socket::SOCK_STREAM, 0
    elsif USE_IO_PIPE
      @rd, @wr = IO.pipe
    else
      @rd, @wr = UNIXSocket.pair
    end

    @rd.define_singleton_method :peeraddr, PEER_ADDR

    @client = Puma::Client.new @rd, env
    @client.supported_http_methods = HTTP_METHODS
  end

  def write_request(request)
    written = 0
    i_limit = 64 * 1024
    size = request.bytesize
    while written < size
      written += @wr.syswrite(request.byteslice(written, i_limit))
      return if @client.try_to_finish
    end
    @client.try_to_finish
  end
end
