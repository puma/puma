require 'test/unit'
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
  end

  def setup
    @server = FakeServer.new
    @app = Puma::App::Status.new(@server, @server)
    @app.auth_token = nil
  end

  def test_bad_token
    @app.auth_token = "abcdef"

    env = { 'PATH_INFO' => "/whatever" }

    status, _, _ = @app.call env

    assert_equal 403, status
  end

  def test_good_token
    @app.auth_token = "abcdef"

    env = {
      'PATH_INFO' => "/whatever",
      'QUERY_STRING' => "token=abcdef"
    }

    status, _, _ = @app.call env

    assert_equal 404, status
  end

  def test_unsupported
    env = { 'PATH_INFO' => "/not-real" }

    status, _, _ = @app.call env

    assert_equal 404, status
  end

  def test_stop
    env = { 'PATH_INFO' => "/stop" }

    status, _ , body = @app.call env

    assert_equal :stop, @server.status
    assert_equal 200, status
    assert_equal ['{ "status": "ok" }'], body
  end

  def test_halt
    env = { 'PATH_INFO' => "/halt" }

    status, _ , body = @app.call env

    assert_equal :halt, @server.status
    assert_equal 200, status
    assert_equal ['{ "status": "ok" }'], body
  end

  def test_stats
    env = { 'PATH_INFO' => "/stats" }

    @server.backlog = 1
    @server.running = 9

    status, _ , body = @app.call env

    assert_equal 200, status
    assert_equal ['{ "backlog": 1, "running": 9 }'], body
  end

end
