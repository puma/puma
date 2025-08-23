# frozen_string_literal: true

require_relative "helper"

require 'puma/client'
require 'puma/const'
require 'puma/puma_http11'

# this file tests both valid and invalid requests using only `Puma::Client'.
# It cannot test behavior with multiple requests, for that, see
# `test_request_invalid_mulitple.rb`


class TestRequestBase < PumaTest
  include Puma::Const

  PEER_ADDR = -> () { ["AF_INET", 80, "127.0.0.1", "127.0.0.1"] }

  GET_PREFIX = "GET / HTTP/1.1\r\nConnection: close\r\n"
  CHUNKED = "1\r\nH\r\n4\r\nello\r\n5\r\nWorld\r\n0\r\n\r\n"

  def create_client(request, &blk)
    env = {}
    @rd, @wr = IO.pipe

    @rd.define_singleton_method :peeraddr, PEER_ADDR

    @client = Puma::Client.new @rd, env
    @parser = @client.instance_variable_get :@parser
    yield if blk

    written = 0
    ttl = request.bytesize - 1
    until written >= ttl
      # Old Rubies, JRuby, and Windows Ruby all have issues with
      # writing large strings to pipe IO's.  Hence, the limit.
      written += @wr.write request[written..(written + 32 * 1024)]
      break if @client.try_to_finish
    end
  end

  def assert_invalid(req, msg, err = Puma::HttpParserError)
    error = assert_raises(err) { create_client req }
    assert_equal msg, error.message
    assert_equal 'close', @client.env[HTTP_CONNECTION],
      "env['HTTP_CONNECTION'] should be set to 'close'"
  end

  def teardown
    @wr&.close
    @rd&.close
    @parser = nil
    @client = nil
  end
end

# Tests requests that require special handling of headers
class TestRequestValid < TestRequestBase

  def test_underscore_header_1
    request = <<~REQ.gsub("\n", "\r\n").rstrip
      GET / HTTP/1.1
      x-forwarded_for: 2.2.2.2
      x-forwarded-for: 1.1.1.1
      Content-Length: 11

      Hello World
    REQ

    create_client request

    if @parser.finished?
      assert_equal "1.1.1.1", @client.env['HTTP_X_FORWARDED_FOR']
      assert_equal "Hello World", @client.body.string
    else
      fail
    end
  end

  def test_underscore_header_2
    hdrs = [
      "X-FORWARDED-FOR: 1.1.1.1",  # proper
      "X-FORWARDED-FOR: 2.2.2.2",  # proper
      "X_FORWARDED-FOR: 3.3.3.3",  # invalid, contains underscore
      "Content-Length: 5",
    ].join "\r\n"

    create_client "#{GET_PREFIX}#{hdrs}\r\n\r\nHello\r\n\r\n"

    if @parser.finished?
      assert_equal "1.1.1.1, 2.2.2.2", @client.env['HTTP_X_FORWARDED_FOR']
      assert_equal "Hello", @client.body.string
    else
      fail
    end
  end

  def test_underscore_header_3
    hdrs = [
      "X_FORWARDED-FOR: 3.3.3.3",  # invalid, contains underscore
      "X-FORWARDED-FOR: 2.2.2.2",  # proper
      "X-FORWARDED-FOR: 1.1.1.1",  # proper
      "Content-Length: 5",
    ].join "\r\n"

    create_client "#{GET_PREFIX}#{hdrs}\r\n\r\nHello\r\n\r\n"

    if @parser.finished?
      assert_equal "2.2.2.2, 1.1.1.1", @client.env['HTTP_X_FORWARDED_FOR']
      assert_equal "Hello", @client.body.string
    else
      fail
    end
  end

  def test_unmaskable_headers
    request = <<~REQ.gsub("\n", "\r\n").rstrip
      GET / HTTP/1.1
      Transfer_Encoding: chunked
      Content_Length: 11

      Hello World
    REQ

    create_client request

    if @parser.finished?
      assert_equal '11', @client.env['HTTP_CONTENT,LENGTH']
      assert_equal 'chunked', @client.env['HTTP_TRANSFER,ENCODING']
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
    assert_invalid "get /?a=1 HTTP/1.1\r\n\r\n",
      "Invalid HTTP format, parsing fails. Bad method get"
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
      "HTTP element HEADER is longer than the (1024 * (80 + 32)) allowed length (was 114930)"

    assert_invalid "GET / HTTP/1.1\r\n#{hdrs}\r\n", msg
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
      'Invalid Content-Length: "5, 5"'
  end

  def test_bad_characters_1
    cl = 'Content-Length: 5.01'

    assert_invalid "#{GET_PREFIX}#{cl}\r\n\r\nHello\r\n\r\n",
     'Invalid Content-Length: "5.01"'
  end

  def test_bad_characters_2
    cl = 'Content-Length: +5'

    assert_invalid "#{GET_PREFIX}#{cl}\r\n\r\nHello\r\n\r\n",
      'Invalid Content-Length: "+5"'
  end

  def test_bad_characters_3
    cl = 'Content-Length: 5 test'

    assert_invalid "#{GET_PREFIX}#{cl}\r\n\r\nHello\r\n\r\n",
    'Invalid Content-Length: "5 test"'
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
      "Invalid Transfer-Encoding, unknown value: 'chunked, gzip'",
      Puma::HttpParserError501
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
      Puma::HttpParserError501
  end

  def test_invalid_multiple
    te = [
      'Transfer-Encoding: x_gzip',
      'Transfer-Encoding: gzip',
      'Transfer-Encoding: chunked'
    ].join "\r\n"

    assert_invalid "#{GET_PREFIX}#{te}\r\n\r\n#{CHUNKED}",
      "Invalid Transfer-Encoding, unknown value: 'x_gzip, gzip, chunked'",
      Puma::HttpParserError501
  end

  def test_single_not_chunked
    te = 'Transfer-Encoding: gzip'

    assert_invalid "#{GET_PREFIX}#{te}\r\n\r\n#{CHUNKED}",
      "Invalid Transfer-Encoding, single value must be chunked: 'gzip'"
  end
end
