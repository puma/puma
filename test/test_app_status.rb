require 'test/unit'
require 'rack'
require 'puma/app/status'

class TestAppStatus < Test::Unit::TestCase
  class FakeServer
    def initialize
      @status = :running
      @backlog = 0
      @running = 0
    end

    attr_reader :status
    attr_accessor :backlog, :running

    def stop
      @status = :stop
    end

    def halt
      @status = :halt
    end

    def stats
      "{}"
    end
  end

  def setup
    @server = FakeServer.new
    @app = Puma::App::Status.new(@server)
    @app.auth_token = nil
  end

  def lint(uri)
    app = Rack::Lint.new @app
    mock_env = Rack::MockRequest.env_for uri
    app.call mock_env
  end

  def test_bad_token
    @app.auth_token = "abcdef"

    status, _, _ = lint('/whatever')

    assert_equal 403, status
  end

  def test_good_token
    @app.auth_token = "abcdef"

    status, _, _ = lint('/whatever?token=abcdef')

    assert_equal 404, status
  end

  def test_unsupported
    status, _, _ = lint('/not-real')

    assert_equal 404, status
  end

  def test_stop
    status, _ , app = lint('/stop')

    assert_equal :stop, @server.status
    assert_equal 200, status
    assert_equal ['{ "status": "ok" }'], app.enum_for.to_a
  end

  def test_halt
    status, _ , app = lint('/halt')

    assert_equal :halt, @server.status
    assert_equal 200, status
    assert_equal ['{ "status": "ok" }'], app.enum_for.to_a
  end

  def test_stats
    @server.backlog = 1
    @server.running = 9
    status, _ , app = lint('/stats')

    assert_equal 200, status
    assert_equal ['{}'], app.enum_for.to_a
  end

  def test_alternate_location
    status, _ , _ = lint('__alternatE_location_/stats')
    assert_equal 200, status
  end
end
