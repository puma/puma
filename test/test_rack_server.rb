# frozen_string_literal: true
require_relative "helper"
require "net/http"

require "rack"

class TestRackServer < Minitest::Test
  parallelize_me!

  class ErrorChecker
    def initialize(app)
      @app = app
      @exception = nil
    end

    attr_reader :exception, :env

    def call(env)
      begin
        @app.call(env)
      rescue Exception => e
        @exception = e
        [ 500, {}, ["Error detected"] ]
      end
    end
  end

  class ServerLint < Rack::Lint
    def call(env)
      check_env env

      @app.call(env)
    end
  end

  def setup
    @simple = lambda { |env| [200, { "X-Header" => "Works" }, ["Hello"]] }
    @server = Puma::Server.new @simple
    @port = (@server.add_tcp_listener "127.0.0.1", 0).addr[1]
    @tcp = "http://127.0.0.1:#{@port}"
    @stopped = false
  end

  def stop
    @server.stop(true)
    @stopped = true
  end

  def teardown
    @server.stop(true) unless @stopped
  end

  def test_lint
    @checker = ErrorChecker.new ServerLint.new(@simple)
    @server.app = @checker

    @server.run

    hit(["#{@tcp}/test"])

    stop

    refute @checker.exception, "Checker raised exception"
  end

  def test_large_post_body
    @checker = ErrorChecker.new ServerLint.new(@simple)
    @server.app = @checker

    @server.run

    big = "x" * (1024 * 16)

    Net::HTTP.post_form URI.parse("#{@tcp}/test"),
                 { "big" => big }

    stop

    refute @checker.exception, "Checker raised exception"
  end

  def test_path_info
    input = nil
    @server.app = lambda { |env| input = env; @simple.call(env) }
    @server.run

    hit(["#{@tcp}/test/a/b/c"])

    stop

    assert_equal "/test/a/b/c", input['PATH_INFO']
  end

  def test_after_reply
    closed = false

    @server.app = lambda do |env|
      env['rack.after_reply'] << lambda { closed = true }
      @simple.call(env)
    end

    @server.run

    hit(["#{@tcp}/test"])

    stop

    assert_equal true, closed
  end

  def test_after_reply_exception
    @server.app = lambda do |env|
      env['rack.after_reply'] << lambda { raise ArgumentError, "oops" }
      @simple.call(env)
    end

    @server.run

    socket = TCPSocket.open "127.0.0.1", @port
    socket.puts "GET /test HTTP/1.1\r\n"
    socket.puts "Connection: Keep-Alive\r\n"
    socket.puts "\r\n"

    headers = socket.readline("\r\n\r\n")
      .split("\r\n")
      .drop(1)
      .map { |line| line.split(/:\s?/) }
      .to_h

    content_length = headers["Content-Length"].to_i
    real_response_body = socket.read(content_length)

    assert_equal "Hello", real_response_body

    # When after_reply breaks the connection it will write the expected HTTP
    # response followed by a second HTTP response: HTTP/1.1 500
    #
    # This sleeps to give the server time to write the invalid/extra HTTP
    # response.
    #
    # * If we can read from the socket, we know that extra content has been
    #   written to the connection and assert that it's our erroneous 500
    #   response.
    # * If we would block trying to read from the socket, we can assume that
    #   the erroneous 500 response wasn't/won't be written.
    sleep 0.1
    assert_raises IO::WaitReadable do
      content = socket.read_nonblock(12)
      refute_includes content, "500"
    end

    socket.close

    stop
  end

  def test_common_logger
    log = StringIO.new

    logger = Rack::CommonLogger.new(@simple, log)

    @server.app = logger

    @server.run

    hit(["#{@tcp}/test"])

    stop

    assert_match %r!GET /test HTTP/1\.1!, log.string
  end
end
