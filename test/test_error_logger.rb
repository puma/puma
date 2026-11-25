# frozen_string_literal: true

require 'puma/error_logger'
require_relative "helper"

class TestErrorLogger < PumaTest
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

    assert_includes err, '#<StandardError: ready>'
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

    assert_includes err, '("GET /debug" - (8.8.8.8))'
  end

  def test_info_with_request_with_query_param
    env = {
      'REQUEST_METHOD' => 'GET',
      'PATH_INFO' => '/debug',
      'HTTP_X_FORWARDED_FOR' => '8.8.8.8',
      'QUERY_STRING' => 'b=test'
    }
    req = Req.new(env, '{"hello":"world"}')

    _, err = capture_io do
      Puma::ErrorLogger.stdio.info(error: StandardError.new, req: req)
    end

    assert_includes err,  'GET /debug?b=test" - (8.8.8.8))'
  end

  def test_info_with_text
    _, err = capture_io do
      Puma::ErrorLogger.stdio.info(text: 'The client disconnected while we were reading data')
    end

    assert_includes err, 'The client disconnected while we were reading data'
  end

  def test_info_text_with_newline_is_logged_as_single_line
    _, err = capture_io do
      Puma::ErrorLogger.stdio.info(text: "line1\nline2")
    end

    assert_equal 1, err.count("\n")
    assert_includes err, 'line1\x0Aline2'
  end

  def test_info_error_message_with_escape_control_character_is_escaped
    _, err = capture_io do
      Puma::ErrorLogger.stdio.info(error: StandardError.new("a\x1bRED"))
    end

    assert_includes err, '\x1B'
    refute_includes err.b, "\x1b".b
  end

  def test_info_error_message_with_carriage_return_control_character_is_escaped
    _, err = capture_io do
      Puma::ErrorLogger.stdio.info(error: StandardError.new("bad\rtail"))
    end

    assert_includes err, '\x0D'
    refute_includes err, "\r"
  end

  def test_info_request_title_with_tab_is_escaped
    env = {
      'REQUEST_METHOD' => 'GET',
      'PATH_INFO' => '/debug',
      'HTTP_X_FORWARDED_FOR' => "8.8.8.8\tproxy"
    }
    req = Req.new(env, '{"hello":"world"}')

    _, err = capture_io do
      Puma::ErrorLogger.stdio.info(error: StandardError.new('boom'), req: req)
    end

    assert_includes err, '\x09'
    refute_includes err, "\t"
  end

  def test_info_text_with_unicode_control_characters_is_escaped
    _, err = capture_io do
      Puma::ErrorLogger.stdio.info(text: "a\u009B31m\u0085\u2028b")
    end

    assert_equal 1, err.count("\n")
    assert_includes err, 'a\xC2\x9B31m\xC2\x85\xE2\x80\xA8b'
  end

  def test_info_text_with_utf8_is_unchanged
    _, err = capture_io do
      Puma::ErrorLogger.stdio.info(text: 'José 日本')
    end

    assert_includes err, 'José 日本'
  end

  def test_info_text_with_bytes_that_are_not_utf8_is_escaped
    _, err = capture_io do
      Puma::ErrorLogger.stdio.info(text: "Jos\xE9 \x9B31m".b)
    end

    assert_includes err, 'Jos\xE9 \x9B31m'
    assert_predicate err, :valid_encoding?
  end

  def test_debug_without_debug_mode
    _, err = capture_io do
      Puma::ErrorLogger.stdio.debug(text: 'blank')
    end

    assert_empty err
  end

  def test_debug_with_debug_mode
    with_temp_env({ "PUMA_DEBUG": "1" }) do
      _, err = capture_io do
        Puma::ErrorLogger.stdio.debug(text: 'non-blank')
      end

      assert_includes err, 'non-blank'
    end
  end

  def test_debug_backtrace_logging
    with_temp_env({ "PUMA_DEBUG": "1" }) do
      def dummy_error
        raise StandardError.new('non-blank')
      rescue => e
        Puma::ErrorLogger.stdio.debug(error: e)
      end

      _, err = capture_io do
        dummy_error
      end

      assert_includes err, "non-blank"

      include_str =
        case
        when Puma::IS_MRI && RUBY_VERSION < '3.4'
          ":in `dummy_error'" # beginning backtick
        when Puma::IS_JRUBY
          ":in 'dummy_error'" # beginning apostrophe/single quote
        else
          ":in 'TestErrorLogger#dummy_error'"
        end

      assert_includes err, include_str
    end
  end
end
