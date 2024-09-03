require 'puma/error_logger'
require_relative "helper"

class TestErrorLogger < Minitest::Test
  Req = Struct.new(:env, :body)

  def test_stdio
    error_logger = Puma::ErrorLogger.stdio

    assert_equal STDERR, error_logger.ioerr
  end


  def test_stdio_respects_sync
    error_logger = Puma::ErrorLogger.stdio

    assert_equal STDERR.sync, error_logger.ioerr.sync
    assert_equal STDERR, error_logger.ioerr
  end

  def test_info_with_only_error
    _, err = capture_io do
      Puma::ErrorLogger.stdio.info(error: StandardError.new('ready'))
    end

    assert_match %r!#<StandardError: ready>!, err
  end

  def test_info_with_request
    env = {
      'REQUEST_METHOD' => 'GET',
      'PATH_INFO' => '/debug',
      'HTTP_X_FORWARDED_FOR' => '8.8.8.8'
    }
    req = Req.new(env, '{"hello":"world"}')

    _, err = capture_io do
      Puma::ErrorLogger.stdio.info(error: StandardError.new, req: req)
    end

    assert_match %r!\("GET /debug" - \(8\.8\.8\.8\)\)!, err
  end

  def test_info_with_text
    _, err = capture_io do
      Puma::ErrorLogger.stdio.info(text: 'The client disconnected while we were reading data')
    end

    assert_match %r!The client disconnected while we were reading data!, err
  end

  def test_debug_without_debug_mode
    _, err = capture_io do
      Puma::ErrorLogger.stdio.debug(text: 'blank')
    end

    assert_empty err
  end

  def test_debug_with_debug_mode
    with_debug_mode do
      _, err = capture_io do
        Puma::ErrorLogger.stdio.debug(text: 'non-blank')
      end

      assert_match %r!non-blank!, err
    end
  end

  def test_debug_backtrace_logging
    with_debug_mode do
      def dummy_error
        raise StandardError.new('non-blank')
      rescue => e
        Puma::ErrorLogger.stdio.debug(error: e)
      end

      _, err = capture_io do
        dummy_error
      end

      assert_match %r!non-blank!, err
      assert_match %r!:in [`'](TestErrorLogger#)?dummy_error'!, err
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
