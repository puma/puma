# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/test_puma/puma_socket"
require "puma/events"
require "puma/server"
require "net/http"
require "nio"

require "rack"
require "rack/body_proxy"

# Tests check both the proper passing of the socket to the app, and also calling
# of `body.close` on the response body.  Rack spec is unclear as to whether
# calling close is expected.
#
# The sleep statements may not be needed for local CI, but are needed
# for use with GitHub Actions...

class TestPumaServerHijack < PumaTest
  parallelize_me!

  include TestPuma
  include TestPuma::PumaSocket

  HOST = HOST4

  def setup
    @host = HOST

    @ios = []

    @app = ->(env) { [200, {}, [env['rack.url_scheme']]] }

    @log_writer = Puma::LogWriter.strings
    @events = Puma::Events.new
  end

  def teardown
    return if skipped?
    @server.stop(true)
    assert_empty @log_writer.stdout.string
    assert_empty @log_writer.stderr.string
  end

  def server_run(**options, &block)
    options[:log_writer]  ||= @log_writer
    options[:min_threads] ||= 1
    options[:max_threads] ||= 1
    @server = Puma::Server.new block || @app, @events, options
    @bind_port = (@server.add_tcp_listener @host, 0).addr[1]
    @server.run
    min_threads = options[:min_threads]
    # below may help with intermittent failures Aug-2025
    until @server.running >= min_threads
      Thread.pass
      sleep 0.01
    end unless Puma::IS_MRI
  end

  # Full hijack does not return headers
  def test_full_hijack_body_close
    @body_closed = false
    server_run do |env|
      io = env['rack.hijack'].call
      io.syswrite 'Server listening'
      io.wait_readable 2
      io.syswrite io.sysread(256)
      body = ::Rack::BodyProxy.new([]) { @body_closed = true }
      [200, {}, body]
    end

    sock = send_http GET_11

    sock.wait_readable 2
    assert_equal "Server listening", sock.sysread(256)

    sock.syswrite "this should echo"
    assert_equal "this should echo", sock.sysread(256)
    Thread.pass
    sleep 0.001 # intermittent failure, may need to increase in CI
    assert @body_closed, "Reponse body must be closed"
  end

  def test_101_body
    headers = {
      'Upgrade' => 'websocket',
      'Connection' => 'Upgrade',
      'Sec-WebSocket-Accept' => 's3pPLMBiTxaQ9kYGzzhZRbK+xOo=',
      'Sec-WebSocket-Protocol' => 'chat'
    }

    body = -> (io) {
      # below for TruffleRuby error with io.sysread
      # Read Errno::EAGAIN: Resource temporarily unavailable
      io.wait_readable 0.1
      io.syswrite io.sysread(256)
      io.close
    }

    server_run do |env|
      [101, headers, body]
    end

    sock = send_http GET_11
    response = sock.read_response
    echo_msg = "This should echo..."
    sock.syswrite echo_msg

    assert_includes response.headers, 'connection: Upgrade'
    sock.wait_readable 0.2 # for TruffleRuby Errno::EAGAIN
    assert_equal echo_msg, sock.sysread(256)
  end

  def test_101_header
    headers = {
      'Upgrade' => 'websocket',
      'Connection' => 'Upgrade',
      'Sec-WebSocket-Accept' => 's3pPLMBiTxaQ9kYGzzhZRbK+xOo=',
      'Sec-WebSocket-Protocol' => 'chat',
      'rack.hijack' => -> (io) {
        # below for TruffleRuby error with io.sysread
        # Read Errno::EAGAIN: Resource temporarily unavailable
        io.wait_readable 0.1
        io.syswrite io.sysread(256)
        io.close
      }
    }

    server_run do |env|
      [101, headers, []]
    end

    sock = send_http GET_11
    response = sock.read_response
    echo_msg = "This should echo..."
    sock.syswrite echo_msg

    assert_includes response.headers, 'connection: Upgrade'
    sock.wait_readable 0.2 # for TruffleRuby Errno::EAGAIN
    assert_equal echo_msg, sock.sysread(256)
  end

  def test_http_10_header_with_content_length
    body_parts = ['abc', 'de']

    server_run do
      hijack_lambda = proc do | io |
        io.write(body_parts[0])
        io.write(body_parts[1])
        io.close
      end
      [200, {"Content-Length" => "5", 'rack.hijack' => hijack_lambda}, nil]
    end

    # using sysread may only receive part of the response
    response = send_http_read_response "GET / HTTP/1.0\r\nConnection: close\r\n\r\n"

    assert_equal "HTTP/1.0 200 OK\r\ncontent-length: 5\r\n\r\nabcde", response
  end

  def test_partial_hijack_body_closes_body
    skip 'Not supported with Rack 1.x' if Rack.release.start_with? '1.'
    @available = true
    hdrs = { 'Content-Type' => 'text/plain' }
    body = ::Rack::BodyProxy.new(HIJACK_LAMBDA) { @available = true }
    partial_hijack_closes_body(hdrs, body)
  end

  def test_partial_hijack_header_closes_body_correct_precedence
    skip 'Not supported with Rack 1.x' if Rack.release.start_with? '1.'
    @available = true
    incorrect_lambda = ->(io) {
      io.syswrite 'incorrect body.call'
      io.close
    }
    hdrs = { 'Content-Type' => 'text/plain', 'rack.hijack' => HIJACK_LAMBDA}
    body = ::Rack::BodyProxy.new(incorrect_lambda) { @available = true }
    partial_hijack_closes_body(hdrs, body)
  end

  HIJACK_LAMBDA = ->(io) {
    io.syswrite 'hijacked'
    io.close
  }

  def partial_hijack_closes_body(hdrs, body)
    server_run do
      if @available
        @available = false
        [200, hdrs, body]
      else
        [500, { 'Content-Type' => 'text/plain' }, ['incorrect']]
      end
    end

    sock1 = send_http GET_11
    sleep (Puma::IS_WINDOWS || !Puma::IS_MRI ? 0.3 : 0.1)
    response1 = sock1.read_response

    sleep 0.01 # time for close block to be called ?

    sock2 = send_http GET_11
    sleep (Puma::IS_WINDOWS || !Puma::IS_MRI ? 0.3 : 0.1)
    response2 = sock2.read_response

    assert_operator response1, :end_with?, 'hijacked'
    assert_operator response2, :end_with?, 'hijacked'
  end
end
