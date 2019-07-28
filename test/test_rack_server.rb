# frozen_string_literal: true
require_relative "helper"

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
    @server.add_tcp_listener "127.0.0.1", 0

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

    hit(["http://127.0.0.1:#{ @server.connected_port }/test"])

    stop

    refute @checker.exception, "Checker raised exception"
  end

  def test_large_post_body
    @checker = ErrorChecker.new ServerLint.new(@simple)
    @server.app = @checker

    @server.run

    big = "x" * (1024 * 16)

    Net::HTTP.post_form URI.parse("http://127.0.0.1:#{ @server.connected_port }/test"),
                 { "big" => big }

    stop

    refute @checker.exception, "Checker raised exception"
  end

  def test_path_info
    input = nil
    @server.app = lambda { |env| input = env; @simple.call(env) }
    @server.run

    hit(["http://127.0.0.1:#{ @server.connected_port }/test/a/b/c"])

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

    hit(["http://127.0.0.1:#{ @server.connected_port }/test"])

    stop

    assert_equal true, closed
  end

  def test_common_logger
    log = StringIO.new

    logger = Rack::CommonLogger.new(@simple, log)

    @server.app = logger

    @server.run

    hit(["http://127.0.0.1:#{ @server.connected_port }/test"])

    stop

    assert_match %r!GET /test HTTP/1\.1!, log.string
  end
end
