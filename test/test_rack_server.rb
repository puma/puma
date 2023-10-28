# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/test_puma/server_in_process"

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

class TestRackServer < TestPuma::ServerInProcess
  parallelize_me!

  STR_1KB = "──#{SecureRandom.hex 507}─\n".freeze

  GET_TEST_KA = "GET /test HTTP/1.1\r\nConnection: Keep-Alive\r\n\r\n"

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
    @simple = ->(env) { [200, { "x-header" => "Works" }, ["Hello"]] }
  end

  def test_lint
    checker = ErrorChecker.new ServerLint.new(@simple)

    server_run app: checker

    send_http GET_TEST_KA

    refute checker.exception, "Checker raised exception"
  end

  def test_large_post_body
    checker = ErrorChecker.new ServerLint.new(@simple)

    server_run app: checker

    big = "x" * (1024 * 16)

    form_body = "big=#{big}"

    req = <<~REQ.gsub("\n", "\r\n").strip
      POST /search HTTP/1.1
      Content-Type: application/x-www-form-urlencoded
      Content-Length: #{form_body.bytesize}

      #{form_body}
    REQ

    body = send_http_read_resp_body req

    refute checker.exception, "Checker raised exception"
    assert_equal 'Hello', body
  end

  def test_path_info
    server_run app: ->(env) { [200, {}, [env['PATH_INFO']]] }

    body = send_http_read_resp_body "GET /test/a/b/c HTTP/1.0\r\n\r\n"

    assert_equal '/test/a/b/c', body
  end

  def test_after_reply
    after_reply_called = false

    server_run app: ->(env) do
      env['rack.after_reply'] << -> { after_reply_called = true }
      @simple.call(env)
    end

    body = send_http_read_resp_body "GET /test HTTP/1.0\r\n\r\n"

    assert_equal 'Hello', body
    sleep 0.05 # intermittent failures without
    assert_equal true, after_reply_called
  end

  def test_after_reply_exception
    server_run app: ->(env) do
      env['rack.after_reply'] << lambda { raise ArgumentError, "oops" }
      @simple.call(env)
    end

    socket = send_http GET_TEST_KA

    body = socket.read_body

    assert_equal "Hello", body

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
  end

  def test_rack_body_proxy
    closed = false
    body = Rack::BodyProxy.new(["Hello"]) { closed = true }

    server_run app: ->(env) { [200, { "X-Header" => "Works" }, body] }

    body = send_http_read_resp_body "GET /test HTTP/1.0\r\n\r\n"

    assert_equal "Hello", body
    assert_equal true, closed
  end

  def test_rack_body_proxy_content_length
    str_ary = %w[0123456789 0123456789 0123456789 0123456789]
    str_ary_bytes = str_ary.sum(&:bytesize)

    body = Rack::BodyProxy.new(str_ary) { }

    server_run app: ->(env) { [200, { "X-Header" => "Works" }, body] }

    headers = send_http_read_response(GET_TEST_KA).headers_hash

    if Rack.release.start_with? '1.'
      assert_equal "chunked", headers["transfer-encoding"]
    else
      assert_equal str_ary_bytes, headers["content-length"].to_i
    end
  end

  def test_common_logger
    log = StringIO.new

    logger = Rack::CommonLogger.new(@simple, log)

    server_run app: logger

    response = send_http_read_response GET_TEST_KA

    if Rack.release < '2.0'
      assert_equal 'Hello', response.decode_body
    else
      assert_equal 'Hello', response.body
    end
    sleep 0.05 # may see empty string otherwise...
    assert_includes log.string, 'GET /test HTTP/1.1'
  end

  def test_rack_chunked_array1
    body = [STR_1KB]
    app = lambda { |env| [200, { 'content-type' => 'text/plain; charset=utf-8' }, body] }
    rack_app = Rack::Chunked.new app
    server_run app: rack_app

    resp = send_http_read_response

    assert_equal 'chunked', resp.headers_hash['transfer-encoding']
    assert_equal STR_1KB, resp.decode_body.force_encoding(Encoding::UTF_8)
  end if Rack.release < '3.1'

  def test_rack_chunked_array10
    body = Array.new 10, STR_1KB
    app = lambda { |env| [200, { 'content-type' => 'text/plain; charset=utf-8' }, body] }
    rack_app = Rack::Chunked.new app
    server_run app: rack_app

    resp = send_http_read_response

    assert_equal 'chunked', resp.headers_hash['transfer-encoding']
    assert_equal STR_1KB * 10, resp.decode_body.force_encoding(Encoding::UTF_8)
  end if Rack.release < '3.1'

  def test_puma_enum
    body = Array.new(10, STR_1KB).to_enum
    server_run app:  lambda { |env| [200, { 'content-type' => 'text/plain; charset=utf-8' }, body] }

    resp = send_http_read_response

    assert_equal 'chunked', resp.headers_hash['transfer-encoding']
    assert_equal STR_1KB * 10, resp.decode_body.force_encoding(Encoding::UTF_8)
  end
end
