require_relative "helper"
require_relative "helpers/test_puma/puma_socket"

# These tests check for invalid request headers and metadata.
# Content-Length, Transfer-Encoding, and chunked body size
# values are checked for validity
#
# See https://httpwg.org/specs/rfc9112.html
#
# https://httpwg.org/specs/rfc9112.html#body.content-length     Content-Length
# https://httpwg.org/specs/rfc9112.html#field.transfer-encoding Transfer-Encoding
# https://httpwg.org/specs/rfc9112.html#chunked.encoding        Chunked Transfer Coding
#
class TestRequestInvalid < PumaTest
  # running parallel seems to take longer...
  # parallelize_me! unless JRUBY_HEAD

  include TestPuma
  include TestPuma::PumaSocket

  GET_PREFIX = "GET / HTTP/1.1\r\nConnection: close\r\n"
  CHUNKED = "1\r\nH\r\n4\r\nello\r\n5\r\nWorld\r\n0\r\n\r\n"

  HOST = HOST4

  STATUS_CODES = ::Puma::HTTP_STATUS_CODES

  HEADERS_413 = [
    "Connection: close",
    "Content-Length: #{STATUS_CODES[413].bytesize}"
  ]

  def setup
    @host = HOST
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
    options = {}
    options[:log_writer]  = @log_writer
    options[:min_threads] = 1
    @server = Puma::Server.new app, nil, options
    @bind_port = (@server.add_tcp_listener @host, 0).addr[1]
    @server.run
    sleep 0.15 if Puma::IS_JRUBY

    @error_on_closed = if Puma::IS_MRI
      if Puma::IS_OSX
        [Errno::ECONNRESET, EOFError]
      elsif Puma::IS_WINDOWS
        [Errno::ECONNABORTED]
      else
        [EOFError]
      end
    elsif Puma::IS_OSX && !Puma::IS_JRUBY # TruffleRuby
      [Errno::ECONNRESET, EOFError]
    else
      [EOFError]
    end
  end

  def teardown
    @server.stop(true)
  end

  def server_run(**options, &block)
    options[:log_writer]  ||= @log_writer
    options[:min_threads] ||= 1
    @server = Puma::Server.new block || @app, nil, options
    @bind_port = (@server.add_tcp_listener @host, 0).addr[1]
    @server.run
  end

  def assert_status(request, status = 400, socket: nil)
    response = if socket
      socket.req_write(request).read_response
    else
      socket = new_socket
      socket.req_write(request).read_response
    end

    re = /\AHTTP\/1\.[01] #{status}/

    assert_match re, response, "'#{response[/[^\r]+/]}' should be #{status}"

    if status >= 400
      if @server.leak_stack_on_error
        cl = response.headers_hash['Content-Length'].to_i
        refute_equal 0, cl
      end
      socket.req_write GET_11
      assert_raises(*@error_on_closed) { socket.read_response }
    end
  end

  # ──────────────────────────────────── below are oversize path length

  def test_oversize_path
    path = "/#{'a' * 8_500}"

    assert_status  "GET #{path} HTTP/1.1\r\n\r\n"
  end

  def test_oversize_path_keep_alive
    path = "/#{'a' * 8_500}"

    socket = new_socket

    assert_status  "GET / HTTP/1.1\r\n\r\n", 200, socket: socket

    assert_status  "GET #{path} HTTP/1.1\r\n\r\n", socket: socket
  end

  # ──────────────────────────────────── below are invalid Content-Length

  def test_content_length_multiple
    te = [
      'Content-Length: 5',
      'Content-Length: 5'
    ].join "\r\n"

    assert_status "#{GET_PREFIX}#{te}\r\n\r\nHello\r\n\r\n"
  end

  def test_content_length_bad_characters_1
    te = 'Content-Length: 5.01'

    assert_status "#{GET_PREFIX}#{te}\r\n\r\nHello\r\n\r\n"
  end

  def test_content_length_bad_characters_2
    te = 'Content-Length: +5'

    assert_status "#{GET_PREFIX}#{te}\r\n\r\nHello\r\n\r\n"
  end

  def test_content_length_bad_characters_3
    te = 'Content-Length: 5 test'

    assert_status "#{GET_PREFIX}#{te}\r\n\r\nHello\r\n\r\n"
  end

  def test_content_length_bad_characters_1_keep_alive
    socket = new_socket

    assert_status "GET / HTTP/1.1\r\n\r\n", 200, socket: socket

    cl = 'Content-Length: 5.01'

    assert_status "#{GET_PREFIX}#{cl}\r\n\r\nHello\r\n\r\n", socket: socket
  end

  # ──────────────────────────────────── below are invalid Transfer-Encoding

  def test_transfer_encoding_chunked_not_last
    te = [
      'Transfer-Encoding: chunked',
      'Transfer-Encoding: gzip'
    ].join "\r\n"

    assert_status "#{GET_PREFIX}#{te}\r\n\r\n#{CHUNKED}"
  end

  def test_transfer_encoding_chunked_multiple
    te = [
      'Transfer-Encoding: chunked',
      'Transfer-Encoding: gzip',
      'Transfer-Encoding: chunked'
    ].join "\r\n"

    assert_status "#{GET_PREFIX}#{te}\r\n\r\n#{CHUNKED}"
  end

  def test_transfer_encoding_invalid_single
    te = 'Transfer-Encoding: xchunked'

    assert_status "#{GET_PREFIX}#{te}\r\n\r\n#{CHUNKED}", 501
  end

  def test_transfer_encoding_invalid_multiple
    te = [
      'Transfer-Encoding: x_gzip',
      'Transfer-Encoding: gzip',
      'Transfer-Encoding: chunked'
    ].join "\r\n"

    assert_status "#{GET_PREFIX}#{te}\r\n\r\n#{CHUNKED}", 501
  end

  def test_transfer_encoding_single_not_chunked
    te = 'Transfer-Encoding: gzip'

    assert_status "#{GET_PREFIX}#{te}\r\n\r\n#{CHUNKED}"
  end

  # ──────────────────────────────────── below are invalid chunked size

  def test_chunked_size_bad_characters_1
    te = 'Transfer-Encoding: chunked'
    chunked ='5.01'

    assert_status "#{GET_PREFIX}#{te}\r\n\r\n" \
      "1\r\nh\r\n#{chunked}\r\nHello\r\n0\r\n\r\n"
  end

  def test_chunked_size_bad_characters_2
    te = 'Transfer-Encoding: chunked'
    chunked ='+5'

    assert_status "#{GET_PREFIX}#{te}\r\n\r\n" \
      "1\r\nh\r\n#{chunked}\r\nHello\r\n0\r\n\r\n"
  end

  def test_chunked_size_bad_characters_3
    te = 'Transfer-Encoding: chunked'
    chunked ='5 bad'

    assert_status "#{GET_PREFIX}#{te}\r\n\r\n" \
      "1\r\nh\r\n#{chunked}\r\nHello\r\n0\r\n\r\n"
  end

  def test_chunked_size_bad_characters_4
    te = 'Transfer-Encoding: chunked'
    chunked ='0xA'

    assert_status "#{GET_PREFIX}#{te}\r\n\r\n" \
      "1\r\nh\r\n#{chunked}\r\nHelloHello\r\n0\r\n\r\n"
  end

  # size is less than bytesize, 4 < 'world'.bytesize
  def test_chunked_size_mismatch_1
    te = 'Transfer-Encoding: chunked'
    chunked =
      "5\r\nHello\r\n" \
      "4\r\nWorld\r\n" \
      "0\r\n\r\n"

    assert_status "#{GET_PREFIX}#{te}\r\n\r\n#{chunked}"
  end

  # size is greater than bytesize, 6 > 'world'.bytesize
  def test_chunked_size_mismatch_2
    te = 'Transfer-Encoding: chunked'
    chunked =
      "5\r\nHello\r\n" \
      "6\r\nWorld\r\n" \
      "0\r\n\r\n"

    assert_status "#{GET_PREFIX}#{te}\r\n\r\n#{chunked}"
  end

  def test_underscore_header_1
    hdrs = [
      "X-FORWARDED-FOR: 1.1.1.1",  # proper
      "X-FORWARDED-FOR: 2.2.2.2",  # proper
      "X_FORWARDED-FOR: 3.3.3.3",  # invalid, contains underscore
      "Content-Length: 5",
    ].join "\r\n"

    response = send_http_read_response "#{GET_PREFIX}#{hdrs}\r\n\r\nHello\r\n\r\n"

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

    response = send_http_read_response "#{GET_PREFIX}#{hdrs}\r\n\r\nHello\r\n\r\n"

    assert_includes response, "HTTP_X_FORWARDED_FOR = 2.2.2.2, 1.1.1.1"
    refute_includes response, "3.3.3.3"
  end


  # ──────────────────────────────────── below have http_content_length_limit set

  # Sets the server to have a http_content_length_limit of 190 kB, then sends a
  # 200 kB body with Content-Length set to the same.
  # Verifies that the connection is closed properly.
  def __test_http_11_req_oversize_content_length
    lleh_err = nil

    lleh = -> (err) {
      lleh_err = err
      [500, {'Content-Type' => 'text/plain'}, ['error']]
    }
    long_string = 'a' * 200_000
    server_run(http_content_length_limit: 190_000, lowlevel_error_handler: lleh) { [200, {}, ['Hello World']] }

    socket = send_http "GET / HTTP/1.1\r\nConnection: Keep-Alive\r\nContent-Length: 200000\r\n\r\n" \
      "#{long_string}"

    response = socket.read_response

    # Content Too Large
    assert_equal "HTTP/1.1 413 #{STATUS_CODES[413]}", response.status
    assert_equal HEADERS_413, response.headers

    sleep 0.5
    refute lleh_err
    assert_raises(Errno::ECONNRESET) { socket << GET_11 }
  end

  # Sets the server to have a http_content_length_limit of 100 kB, then sends a
  # 200 kB chunked body.  Verifies that the connection is closed properly.
  def __test_http_11_req_oversize_chunked
    chunk_length = 20_000
    chunk_part_qty = 10

    lleh_err = nil

    lleh = -> (err) {
      lleh_err = err
      [500, {'Content-Type' => 'text/plain'}, ['error']]
    }
    long_string = 'a' * chunk_length
    long_string_part = "#{long_string.bytesize.to_s 16}\r\n#{long_string}\r\n"
    long_chunked = "#{long_string_part * chunk_part_qty}0\r\n\r\n"

    server_run(
      http_content_length_limit: 100_000,
      lowlevel_error_handler: lleh
    ) { [200, {}, ['Hello World']] }

    socket = send_http "GET / HTTP/1.1\r\nConnection: Keep-Alive\r\n" \
      "Transfer-Encoding: chunked\r\n\r\n#{long_chunked}"

    response = socket.read_response

    # Content Too Large
    assert_equal "HTTP/1.1 413 #{STATUS_CODES[413]}", response.status
    assert_equal HEADERS_413, response.headers

    sleep 0.5
    refute lleh_err

    assert_raises(Errno::ECONNRESET) { socket << GET_11 }
  end

  # Sets the server to have a http_content_length_limit of 190 kB, then sends a
  # 200 kB body with Content-Length set to the same.
  # Verifies that the connection is closed properly.
  def __test_http_11_req_oversize_no_content_length
    lleh_err = nil

    lleh = -> (err) {
      lleh_err = err
      [500, {'Content-Type' => 'text/plain'}, ['error']]
    }
    long_string = 'a' * 200_000
    server_run(http_content_length_limit: 190_000, lowlevel_error_handler: lleh) { [200, {}, ['Hello World']] }

    socket = send_http "GET / HTTP/1.1\r\nConnection: Keep-Alive\r\n\r\n" \
      "#{long_string}"

    response = socket.read_response

    # Content Too Large
    assert_equal "HTTP/1.1 413 #{STATUS_CODES[413]}", response.status
    assert_equal HEADERS_413, response.headers

    sleep 0.5
    refute lleh_err
    assert_raises(Errno::ECONNRESET) { socket << GET_11 }
  end
end
