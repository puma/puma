# frozen_string_literal: true
require_relative "helper"
require "net/http"

# don't load Rack, as it autoloads everything
begin
  require "rack/body_proxy"
  require "rack/lint"
  require "rack/version"
  require "rack/common_logger"
rescue LoadError # Rack 1.6
  require "rack"
end

# Rack::Chunked is loaded by Rack v2, needs to be required by Rack 3.0,
# and is removed in Rack 3.1
require "rack/chunked" if Rack.release.start_with? '3.0'

require "nio"

class TestRackServer < Minitest::Test
  parallelize_me!

  HOST = '127.0.0.1'

  STR_1KB = "──#{SecureRandom.hex 507}─\n".freeze

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
      if Rack.release < '3'
        check_env env
      else
        Wrapper.new(@app, env).check_environment env
      end

      @app.call(env)
    end
  end

  def setup
    @simple = lambda { |env| [200, { "x-header" => "Works" }, ["Hello"]] }
    @server = Puma::Server.new @simple
    @port = (@server.add_tcp_listener HOST, 0).addr[1]
    @tcp = "http://#{HOST}:#{@port}"
    @stopped = false
  end

  def stop
    @server.stop(true)
    @stopped = true
  end

  def teardown
    @server.stop(true) unless @stopped
  end

  def header_hash(socket)
    t = socket.readline("\r\n\r\n").split("\r\n")
    t.shift; t.map! { |line| line.split(/:\s?/) }
    t.to_h
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

    socket = TCPSocket.open HOST, @port
    socket.puts "GET /test HTTP/1.1\r\n"
    socket.puts "Connection: Keep-Alive\r\n"
    socket.puts "\r\n"

    headers = header_hash socket

    content_length = headers["content-length"].to_i
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

  def test_rack_body_proxy
    closed = false
    body = Rack::BodyProxy.new(["Hello"]) { closed = true }

    @server.app = lambda { |env| [200, { "X-Header" => "Works" }, body] }

    @server.run

    hit(["#{@tcp}/test"])

    stop

    assert_equal true, closed
  end

  def test_rack_body_proxy_content_length
    str_ary = %w[0123456789 0123456789 0123456789 0123456789]
    str_ary_bytes = str_ary.to_ary.inject(0) { |sum, el| sum + el.bytesize }

    body = Rack::BodyProxy.new(str_ary) { }

    @server.app = lambda { |env| [200, { "X-Header" => "Works" }, body] }

    @server.run

    socket = TCPSocket.open HOST, @port
    socket.puts "GET /test HTTP/1.1\r\n"
    socket.puts "Connection: Keep-Alive\r\n"
    socket.puts "\r\n"

    headers = header_hash socket

    socket.close

    stop

    if Rack.release.start_with? '1.'
      assert_equal "chunked", headers["transfer-encoding"]
    else
      assert_equal str_ary_bytes, headers["content-length"].to_i
    end
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

  def test_rack_chunked_array1
    body = [STR_1KB]
    app = lambda { |env| [200, { 'content-type' => 'text/plain; charset=utf-8' }, body] }
    rack_app = Rack::Chunked.new app
    @server.app = rack_app
    @server.run

    resp = Net::HTTP.get_response URI(@tcp)
    assert_equal 'chunked', resp['transfer-encoding']
    assert_equal STR_1KB, resp.body.force_encoding(Encoding::UTF_8)
  end if Rack.release < '3.1'

  def test_rack_chunked_array10
    body = Array.new 10, STR_1KB
    app = lambda { |env| [200, { 'content-type' => 'text/plain; charset=utf-8' }, body] }
    rack_app = Rack::Chunked.new app
    @server.app = rack_app
    @server.run

    resp = Net::HTTP.get_response URI(@tcp)
    assert_equal 'chunked', resp['transfer-encoding']
    assert_equal STR_1KB * 10, resp.body.force_encoding(Encoding::UTF_8)
  end if Rack.release < '3.1'

  def test_puma_enum
    body = Array.new(10, STR_1KB).to_enum
    @server.app = lambda { |env| [200, { 'content-type' => 'text/plain; charset=utf-8' }, body] }
    @server.run

    resp = Net::HTTP.get_response URI(@tcp)
    assert_equal 'chunked', resp['transfer-encoding']
    assert_equal STR_1KB * 10, resp.body.force_encoding(Encoding::UTF_8)
  end
end
