require_relative "helper"
require "puma/events"
require "puma/server"
require "net/http"
require "nio"
require "ipaddr"

class TestPumaServerPartialHijack < Minitest::Test
  parallelize_me!

  def setup
    @host = "127.0.0.1"

    @ios = []

    @app = ->(env) { [200, {}, [env['rack.url_scheme']]] }

    @log_writer = Puma::LogWriter.strings
    @events = Puma::Events.new
  end

  def teardown
    @server.stop(true)
    assert_empty @log_writer.stdout.string
    assert_empty @log_writer.stderr.string

    # Errno::EBADF raised on macOS
    @ios.each do |io|
      begin
        io.close if io.respond_to?(:close) && !io.closed?
        File.unlink io.path if io.is_a? File
      rescue Errno::EBADF
      ensure
        io = nil
      end
    end
  end

  def server_run(**options, &block)
    options[:log_writer]  ||= @log_writer
    options[:min_threads] ||= 1
    @server = Puma::Server.new block || @app, @events, options
    @port = (@server.add_tcp_listener @host, 0).addr[1]
    @server.run
    sleep 0.15 if Puma.jruby?
  end

  # only for shorter bodies!
  def send_http_and_sysread(req)
    send_http(req).sysread 2_048
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

  def test_101_body
    headers = {
      'Upgrade' => 'websocket',
      'Connection' => 'Upgrade',
      'Sec-WebSocket-Accept' => 's3pPLMBiTxaQ9kYGzzhZRbK+xOo=',
      'Sec-WebSocket-Protocol' => 'chat'
    }

    body = -> (io) {
      io.wait_readable 0.1 # TRUFFLE
      io.syswrite io.sysread(256)
      io.close
    }

    server_run do |env|
      [101, headers, body]
    end

    sock = new_connection
    sock.syswrite "GET / HTTP/1.1\r\n\r\n"
    resp = sock.sysread 1_024
    echo_msg = "This should echo..."
    sock.syswrite echo_msg

    assert_includes resp, 'Connection: Upgrade'
    assert_equal echo_msg, sock.sysread(256)
  end

  def test_101_header
    headers = {
      'Upgrade' => 'websocket',
      'Connection' => 'Upgrade',
      'Sec-WebSocket-Accept' => 's3pPLMBiTxaQ9kYGzzhZRbK+xOo=',
      'Sec-WebSocket-Protocol' => 'chat',
      'rack.hijack' => -> (io) {
        io.wait_readable 0.1 # TRUFFLE
        io.syswrite io.sysread(256)
        io.close
      }
    }

    server_run do |env|
      [101, headers, []]
    end

    sock = new_connection
    sock.syswrite "GET / HTTP/1.1\r\n\r\n"
    resp = sock.sysread 1_024
    echo_msg = "This should echo..."
    sock.syswrite echo_msg

    assert_includes resp, 'Connection: Upgrade'
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

    data = send_http_and_read "GET / HTTP/1.0\r\nConnection: close\r\n\r\n"

    assert_equal "HTTP/1.0 200 OK\r\nContent-Length: 5\r\n\r\nabcde", data
  end
end
