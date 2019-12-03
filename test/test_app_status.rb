# frozen_string_literal: true

require_relative "helper"

require "puma/app/status"
require "rack"

class TestAppStatus < Minitest::Test
  parallelize_me!

  class FakeServer
    def initialize
      @status = :running
    end

    attr_reader :status

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
  end

  def lint(uri)
    app = Rack::Lint.new @app
    mock_env = Rack::MockRequest.env_for uri
    app.call mock_env
  end

  # control token and control_action

  def test_missing_control_token_with_control_action
    @app.instance_variable_set(:@control_token, "abcdef")

    status, _, _ = lint('/stop')

    assert_equal 403, status
  end

  def test_invalid_control_token_with_control_action
    @app.instance_variable_set(:@control_token, "abcdef")

    status, _, _ = lint('/stop?token=invalid')

    assert_equal 403, status
  end

  def test_valid_control_token_with_control_action
    @app.instance_variable_set(:@control_token, "abcdef")

    status, _ , app = lint('/stop?token=abcdef')

    assert_equal :stop, @server.status
    assert_equal 200, status
    assert_equal ['{ "status": "ok" }'], app.enum_for.to_a
  end

  # control token and unsupported action

  def test_valid_control_token_with_unsupported_action
    @app.instance_variable_set(:@control_token, "abcdef")

    status, _, _ = lint('/unsupported?token=abcdef')

    assert_equal 404, status
  end

  # control token and status action

  def test_missing_control_token_with_status_action
    @app.instance_variable_set(:@control_token, "abcdef")
    @app.instance_variable_set(:@status_token, "ghijkl")

    status, _, _ = lint('/stats')

    assert_equal 403, status
  end

  def test_missing_control_token_with_status_action_no_control_token_defined
    @app.instance_variable_set(:@control_token, nil)
    @app.instance_variable_set(:@status_token, "ghijkl")

    status, _, app = lint('/stats')

    assert_equal 200, status
    assert_equal ['{}'], app.enum_for.to_a
  end

  def test_missing_control_token_with_status_action_no_status_token_defined
    @app.instance_variable_set(:@control_token, "abcdef")
    @app.instance_variable_set(:@status_token, nil)

    status, _, app = lint('/stats')

    assert_equal 200, status
    assert_equal ['{}'], app.enum_for.to_a
  end

  def test_invalid_control_token_with_status_action
    @app.instance_variable_set(:@control_token, "abcdef")
    @app.instance_variable_set(:@status_token, "ghijkl")

    status, _ , app = lint('/stats?token=invalid')

    assert_equal 403, status
  end

  def test_invalid_control_token_with_status_action_no_control_token_defined
    @app.instance_variable_set(:@control_token, nil)
    @app.instance_variable_set(:@status_token, "ghijkl")

    status, _ , app = lint('/stats?token=abcdef')

    assert_equal 200, status
    assert_equal ['{}'], app.enum_for.to_a
  end

  def test_invalid_control_token_with_status_action_no_status_token_defined
    @app.instance_variable_set(:@control_token, "abcdef")
    @app.instance_variable_set(:@status_token, nil)

    status, _ , app = lint('/stats?token=invalid')

    assert_equal 200, status
    assert_equal ['{}'], app.enum_for.to_a
  end

  def test_valid_control_token_with_status_action
    @app.instance_variable_set(:@control_token, "abcdef")
    @app.instance_variable_set(:@status_token, "ghijkl")

    status, _ , app = lint('/stats?token=abcdef')

    assert_equal 200, status
    assert_equal ['{}'], app.enum_for.to_a
  end

  def test_valid_control_token_with_status_action_no_status_token_defined
    @app.instance_variable_set(:@control_token, "abcdef")
    @app.instance_variable_set(:@status_token, nil)

    status, _ , app = lint('/stats?token=abcdef')

    assert_equal 200, status
    assert_equal ['{}'], app.enum_for.to_a
  end

  # status token and status action

  def test_missing_status_token_with_status_action
    @app.instance_variable_set(:@control_token, "abcdef")
    @app.instance_variable_set(:@status_token, "ghijkl")

    status, _, _ = lint('/stats')

    assert_equal 403, status
  end

  def test_invalid_status_token_with_status_action
    @app.instance_variable_set(:@control_token, "abcdef")
    @app.instance_variable_set(:@status_token, "ghijkl")

    status, _, _ = lint('/stats?token=invalid')

    assert_equal 403, status
  end

  def test_valid_status_token_with_status_action
    @app.instance_variable_set(:@status_token, "ghijkl")

    status, _ , app = lint('/stats?token=ghijkl')

    assert_equal 200, status
    assert_equal ['{}'], app.enum_for.to_a
  end

  # no tokens defined

  def test_unsupported_action
    status, _, _ = lint('/unsupported')

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
    status, _ , app = lint('/stats')

    assert_equal 200, status
    assert_equal ['{}'], app.enum_for.to_a
  end

  def test_alternate_location
    status, _ , _ = lint('__alternatE_location_/stats')
    assert_equal 200, status
  end
end
