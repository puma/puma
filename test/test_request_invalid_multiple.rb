# frozen_string_literal: true

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

class TestRequestInvalidMultiple < PumaTest
  parallelize_me! if Puma::IS_MRI

  include TestPuma
  include TestPuma::PumaSocket

  GET_PREFIX = "GET / HTTP/1.1\r\nconnection: close\r\n"
  CHUNKED = "1\r\nH\r\n4\r\nello\r\n5\r\nWorld\r\n0\r\n\r\n"

  HOST = HOST4

  STATUS_CODES = ::Puma::HTTP_STATUS_CODES

  HEADERS_413 = [
    "connection: close",
    "content-length: #{STATUS_CODES[413].bytesize}"
  ]

  ERROR_ON_CLOSED = [Errno::ECONNABORTED, Errno::ECONNRESET, Errno::EPIPE, EOFError]

  STDERR_STR = 'HTTP parse error, malformed request'

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

    options = {}
    options[:log_writer]  = Puma::LogWriter.strings
    options[:min_threads] = 1
    options[:max_threads] = 1
    @server = Puma::Server.new app, nil, options
    @bind_port = (@server.add_tcp_listener @host, 0).addr[1]
    @server.run
    min_threads = options[:min_threads]
    until @server.running >= min_threads
      Thread.pass
      sleep 0.01
    end
  end

  def teardown
    @server.stop true
  end

  def server_run(**options, &block)
    @server.halt(true) if Puma::IS_JRUBY
    options[:log_writer]  ||= Puma::LogWriter.strings
    options[:min_threads] = 1
    options[:max_threads] = 1
    @server = Puma::Server.new block || @app, nil, options
    @bind_port = (@server.add_tcp_listener @host, 0).addr[1]
    @server.run
    min_threads = options[:min_threads]
    until @server.running >= min_threads
      Thread.pass
      sleep 0.01
    end
  end

  def assert_status(request, status = 400, socket: nil)
    @response = if socket
      socket.req_write(request).read_response
    else
      socket = new_socket
      socket.req_write(request).read_response
    end

    re = /\AHTTP\/1\.[01] #{status}/

    assert_match re, @response, "'#{@response[/[^\r]+/]}' should be #{status}"

    if status >= 400
      if @server.leak_stack_on_error
        cl = @response.headers_hash['content-length'].to_i
        refute_equal 0, cl, "Expected `content-length` header to be non-zero but was `#{cl}`. Headers: #{@response.headers_hash}"
      end
      socket.req_write GET_11
      assert_raises(*ERROR_ON_CLOSED) { socket.read_response }
      assert_includes @server.log_writer.stderr.string, STDERR_STR
    end
  end

  # ──────────────────────────────────── below are oversize path length

  def test_oversize_path_keep_alive
    path = "/#{'a' * 8_500}"

    socket = new_socket

    assert_status "GET / HTTP/1.1\r\n\r\n", 200, socket: socket

    assert_status "GET #{path} HTTP/1.1\r\n\r\n", socket: socket
    assert_includes @response.body, "lib/puma/client.rb"
  end

  # ──────────────────────────────────── below are invalid Content-Length

  def test_content_length_bad_characters_1_keep_alive
    socket = new_socket

    assert_status "GET / HTTP/1.1\r\n\r\n", 200, socket: socket

    cl = 'Content-Length: 5.01'

    assert_status "#{GET_PREFIX}#{cl}\r\n\r\nHello", socket: socket
    assert_includes @response.body, "lib/puma/client.rb"
  end

  # ──────────────────────────────────── below have http_content_length_limit set

  # Sets the server to have a http_content_length_limit of 190 kB, then sends a
  # 200 kB body with Content-Length set to the same.
  # Verifies that the connection is closed properly.
  # @todo Why doesn't this work on Windows?
  def test_http_11_req_oversize_content_length
    lleh_err = nil

    lleh = -> (err) {
      lleh_err = err
      [500, {'Content-Type' => 'text/plain'}, ['error']]
    }
    long_string = 'a' * 200_000
    server_run(http_content_length_limit: 190_000, lowlevel_error_handler: lleh) { [200, {}, ['Hello World']] }

    socket = send_http "GET / HTTP/1.1\r\nConnection: Keep-Alive\r\nContent-Length: 200000\r\n\r\n" \
      "#{long_string}"

    unless Puma::IS_WINDOWS
      response = socket.read_response

      # Content Too Large
      assert_equal "HTTP/1.1 413 #{STATUS_CODES[413]}", response.status
      assert_equal HEADERS_413, response.headers
    end

    refute lleh_err
    sleep 0.1 if Puma::IS_JRUBY || Puma::IS_WINDOWS
    assert_raises(*ERROR_ON_CLOSED) { socket << GET_11 }
  end

  # Sets the server to have a http_content_length_limit of 100 kB, then sends a
  # 200 kB chunked body.  Verifies that the connection is closed properly.
  # @todo Why doesn't this work on Windows?
  def test_http_11_req_oversize_chunked
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

    unless Puma::IS_WINDOWS
      response = socket.read_response

      # Content Too Large
      assert_equal "HTTP/1.1 413 #{STATUS_CODES[413]}", response.status
      assert_equal HEADERS_413, response.headers
    end

    refute lleh_err
    sleep 0.1
    assert_raises(*ERROR_ON_CLOSED) { socket << GET_11 }
  end
end
