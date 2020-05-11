require 'puma/debug_logger'
require_relative "helper"

class TestDebugLogger < Minitest::Test
  Req = Struct.new(:env, :body)

  def setup
    @debug_logger = Puma::DebugLogger.stdio
  end

  def test_stdio
    debug_logger = Puma::DebugLogger.stdio

    assert_equal STDERR, debug_logger.ioerr
  end

  def test_error_dump_if_debug_false
    _, err = capture_io do
      @debug_logger.error_dump(text: 'blank')
    end

    assert_empty err
  end

  def test_error_dump_force
    _, err = capture_io do
      Puma::DebugLogger.stdio.error_dump(text: 'ready', force: true)
    end

    assert_match %r!ready!, err
  end

  def test_error_dump_with_only_error
    with_debug_mode do
      _, err = capture_io do
        Puma::DebugLogger.stdio.error_dump(error: StandardError.new('ready'))
      end

      assert_match %r!#<StandardError: ready>!, err
    end
  end

  def test_error_dump_with_request
    with_debug_mode do

      env = {
        'REQUEST_METHOD' => 'GET',
        'PATH_INFO' => '/debug',
        'HTTP_X_FORWARDED_FOR' => '8.8.8.8'
      }
      req = Req.new(env, '{"hello":"world"}')

      _, err = capture_io do
        Puma::DebugLogger.stdio.error_dump(error: StandardError.new, req: req)
      end

      assert_match %r!Handling request { "GET /debug" - \(8\.8\.8\.8\) }!, err
      assert_match %r!Headers: {"X_FORWARDED_FOR"=>"8\.8\.8\.8"}!, err
      assert_match %r!Body: {"hello":"world"}!, err
    end
  end

  def test_error_dump_with_text
    with_debug_mode do
      _, err = capture_io do
        Puma::DebugLogger.stdio.error_dump(text: 'The client disconnected while we were reading data')
      end

      assert_match %r!The client disconnected while we were reading data!, err
    end
  end

  private

  def with_debug_mode
    original_debug, ENV["PUMA_DEBUG"] = ENV["PUMA_DEBUG"], "1"
    yield
  ensure
    ENV["PUMA_DEBUG"] = original_debug
  end
end
