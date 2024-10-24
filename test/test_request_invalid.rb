require_relative "helper"

# These tests check for invalid request headers and metadata.
# Content-Length, Transfer-Encoding, and chunked body size
# values are checked for validity
#
# See https://datatracker.ietf.org/doc/html/rfc7230
#
# https://datatracker.ietf.org/doc/html/rfc7230#section-3.3.2 Content-Length
# https://datatracker.ietf.org/doc/html/rfc7230#section-3.3.1 Transfer-Encoding
# https://datatracker.ietf.org/doc/html/rfc7230#section-4.1   chunked body size
#
class TestRequestInvalid < Minitest::Test
  # running parallel seems to take longer...
  # parallelize_me! unless JRUBY_HEAD

  GET_PREFIX = "GET / HTTP/1.1\r\nConnection: close\r\n"
  CHUNKED = "1\r\nH\r\n4\r\nello\r\n5\r\nWorld\r\n0\r\n\r\n"

  def setup
    @host = '127.0.0.1'

    @ios = []

    # this app should never be called, used for debugging
    app = ->(env) {
      body = +''
      env.each do |k,v|
        body << "#{k} = #{v}\n"
        if k == 'rack.input'
          body << "#{v.read}\n"
        end
      end
      [200, {}, [body]]
    }

    @log_writer = Puma::LogWriter.strings
    @server = Puma::Server.new app, nil, {log_writer: @log_writer}
    @port = (@server.add_tcp_listener @host, 0).addr[1]
    @server.run
    sleep 0.15 if Puma.jruby?
  end

  def teardown
    @server.stop(true)
    @ios.each { |io| io.close if io && !io.closed? }
  end

  def send_http_and_read(req)
    send_http(req).read
  end

  def send_http(req)
    new_connection << req
  end

  def new_connection
    TCPSocket.new(@host, @port).tap {|sock| @ios << sock}
  end

  def assert_status(str, status = 400)
    assert str.start_with?("HTTP/1.1 #{status}"), "'#{str[/[^\r]+/]}' should be #{status}"
  end

  # ──────────────────────────────────── below are invalid Content-Length

  def test_content_length_multiple
    te = [
      'Content-Length: 5',
      'Content-Length: 5'
    ].join "\r\n"

    data = send_http_and_read "#{GET_PREFIX}#{te}\r\n\r\nHello\r\n\r\n"

    assert_status data
  end

  def test_content_length_bad_characters_1
    te = 'Content-Length: 5.01'

    data = send_http_and_read "#{GET_PREFIX}#{te}\r\n\r\nHello\r\n\r\n"

    assert_status data
  end

  def test_content_length_bad_characters_2
    te = 'Content-Length: +5'

    data = send_http_and_read "#{GET_PREFIX}#{te}\r\n\r\nHello\r\n\r\n"

    assert_status data
  end

  def test_content_length_bad_characters_3
    te = 'Content-Length: 5 test'

    data = send_http_and_read "#{GET_PREFIX}#{te}\r\n\r\nHello\r\n\r\n"

    assert_status data
  end

  # ──────────────────────────────────── below are invalid Transfer-Encoding

  def test_transfer_encoding_chunked_not_last
    te = [
      'Transfer-Encoding: chunked',
      'Transfer-Encoding: gzip'
    ].join "\r\n"

    data = send_http_and_read "#{GET_PREFIX}#{te}\r\n\r\n#{CHUNKED}"

    assert_status data
  end

  def test_transfer_encoding_chunked_multiple
    te = [
      'Transfer-Encoding: chunked',
      'Transfer-Encoding: gzip',
      'Transfer-Encoding: chunked'
    ].join "\r\n"

    data = send_http_and_read "#{GET_PREFIX}#{te}\r\n\r\n#{CHUNKED}"

    assert_status data
  end

  def test_transfer_encoding_invalid_single
    te = 'Transfer-Encoding: xchunked'

    data = send_http_and_read "#{GET_PREFIX}#{te}\r\n\r\n#{CHUNKED}"

    assert_status data, 501
  end

  def test_transfer_encoding_invalid_multiple
    te = [
      'Transfer-Encoding: x_gzip',
      'Transfer-Encoding: gzip',
      'Transfer-Encoding: chunked'
    ].join "\r\n"

    data = send_http_and_read "#{GET_PREFIX}#{te}\r\n\r\n#{CHUNKED}"

    assert_status data, 501
  end

  def test_transfer_encoding_single_not_chunked
    te = 'Transfer-Encoding: gzip'

    data = send_http_and_read "#{GET_PREFIX}#{te}\r\n\r\n#{CHUNKED}"

    assert_status data
  end

  # ──────────────────────────────────── below are invalid chunked size

  def test_chunked_size_bad_characters_1
    te = 'Transfer-Encoding: chunked'
    chunked ='5.01'

    data = send_http_and_read "#{GET_PREFIX}#{te}\r\n\r\n1\r\nh\r\n#{chunked}\r\nHello\r\n0\r\n\r\n"

    assert_status data
  end

  def test_chunked_size_bad_characters_2
    te = 'Transfer-Encoding: chunked'
    chunked ='+5'

    data = send_http_and_read "#{GET_PREFIX}#{te}\r\n\r\n1\r\nh\r\n#{chunked}\r\nHello\r\n0\r\n\r\n"

    assert_status data
  end

  def test_chunked_size_bad_characters_3
    te = 'Transfer-Encoding: chunked'
    chunked ='5 bad'

    data = send_http_and_read "#{GET_PREFIX}#{te}\r\n\r\n1\r\nh\r\n#{chunked}\r\nHello\r\n0\r\n\r\n"

    assert_status data
  end

  def test_chunked_size_bad_characters_4
    te = 'Transfer-Encoding: chunked'
    chunked ='0xA'

    data = send_http_and_read "#{GET_PREFIX}#{te}\r\n\r\n1\r\nh\r\n#{chunked}\r\nHelloHello\r\n0\r\n\r\n"

    assert_status data
  end

  # size is less than bytesize
  def test_chunked_size_mismatch_1
    te = 'Transfer-Encoding: chunked'
    chunked =
      "5\r\nHello\r\n" \
      "4\r\nWorld\r\n" \
      "0"

    data = send_http_and_read "#{GET_PREFIX}#{te}\r\n\r\n#{chunked}\r\n\r\n"

    assert_status data
  end

  # size is greater than bytesize
  def test_chunked_size_mismatch_2
    te = 'Transfer-Encoding: chunked'
    chunked =
      "5\r\nHello\r\n" \
      "6\r\nWorld\r\n" \
      "0"

    data = send_http_and_read "#{GET_PREFIX}#{te}\r\n\r\n#{chunked}\r\n\r\n"

    assert_status data
  end

  def test_underscore_header_1
    hdrs = [
      "X-FORWARDED-FOR: 1.1.1.1",  # proper
      "X-FORWARDED-FOR: 2.2.2.2",  # proper
      "X_FORWARDED-FOR: 3.3.3.3",  # invalid, contains underscore
      "Content-Length: 5",
    ].join "\r\n"

    response = send_http_and_read "#{GET_PREFIX}#{hdrs}\r\n\r\nHello\r\n\r\n"

    assert_includes response, "HTTP_X_FORWARDED_FOR = 1.1.1.1, 2.2.2.2"
    refute_includes response, "3.3.3.3"
  end

  def test_underscore_header_2
    hdrs = [
      "X_FORWARDED-FOR: 3.3.3.3",  # invalid, contains underscore
      "X-FORWARDED-FOR: 2.2.2.2",  # proper
      "X-FORWARDED-FOR: 1.1.1.1",  # proper
      "Content-Length: 5",
    ].join "\r\n"

    response = send_http_and_read "#{GET_PREFIX}#{hdrs}\r\n\r\nHello\r\n\r\n"

    assert_includes response, "HTTP_X_FORWARDED_FOR = 2.2.2.2, 1.1.1.1"
    refute_includes response, "3.3.3.3"
  end
end
