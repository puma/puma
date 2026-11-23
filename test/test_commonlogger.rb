# frozen_string_literal: true

require_relative "helper"

require "puma/util"
require "puma/commonlogger"

class TestCommonLogger < PumaTest
  parallelize_me!

  APP = ->(_env) { [200, {'Content-Length' => '5'}, ['hello']] }

  def env(overrides = {})
    {
      'REQUEST_METHOD'   => 'GET',
      'PATH_INFO'        => '/path',
      'QUERY_STRING'     => '',
      'SERVER_PROTOCOL'  => 'HTTP/1.1',
      'REMOTE_ADDR'      => '127.0.0.1',
      'rack.errors'      => StringIO.new,
      'rack.after_reply' => []
    }.merge overrides
  end

  # CommonLogger documents falling back to rack.errors when no logger is given.
  def test_nil_logger_writes_to_rack_errors
    e = env
    Puma::CommonLogger.new(APP).call e
    e['rack.after_reply'].each(&:call)

    assert_match %r{^127\.0\.0\.1 - - \[.+\] "GET /path HTTP/1\.1" 200 5 },
      e['rack.errors'].string
  end

  def test_nil_logger_writes_to_rack_errors_when_hijacked
    e = env 'rack.hijack_io' => :io
    Puma::CommonLogger.new(APP).call e

    assert_match %r{^127\.0\.0\.1 - - \[.+\] "GET /path HTTP/1\.1" HIJACKED -1 },
      e['rack.errors'].string
  end

  def test_explicit_logger_is_preferred_over_rack_errors
    logger = StringIO.new
    e = env
    Puma::CommonLogger.new(APP, logger).call e
    e['rack.after_reply'].each(&:call)

    assert_includes logger.string, '"GET /path HTTP/1.1" 200 5'
    assert_empty e['rack.errors'].string
  end

  def request_log(env_overrides = {})
    logger = StringIO.new
    e = env(env_overrides)
    Puma::CommonLogger.new(APP, logger).call e
    e['rack.after_reply'].each(&:call)
    logger.string
  end

  def hijack_log(env_overrides = {})
    logger = StringIO.new
    e = env(env_overrides.merge('rack.hijack_io' => :io))
    Puma::CommonLogger.new(APP, logger).call e
    logger.string
  end

  def assert_single_line(log)
    bytes = log.b
    assert_equal 10, bytes.getbyte(-1)
    assert_equal 1, bytes.count("\n")
  end

  def test_remote_user_control_characters_are_escaped
    log = request_log 'REMOTE_USER' => "alice\n10.9.9.9 - admin"
    assert_single_line log
    assert_match %r{\A127\.0\.0\.1 - alice\\x0A10\.9\.9\.9 - admin \[.+\] "GET /path HTTP/1\.1" 200 5 \d+\.\d{4}\n\z}, log

    log = request_log 'REMOTE_USER' => "alice\r"
    assert_single_line log
    assert_includes log, 'alice\\x0D'

    log = request_log 'REMOTE_USER' => "alice\e"
    assert_single_line log
    assert_includes log, 'alice\\x1B'

    log = request_log 'REMOTE_USER' => "alice\x00\x7F"
    assert_single_line log
    assert_includes log, 'alice\\x00\\x7F'

    log = request_log 'REMOTE_USER' => "alice\u009B31m\u0085\u2028\u2029"
    assert_single_line log
    assert_includes log, 'alice\\xC2\\x9B31m\\xC2\\x85\\xE2\\x80\\xA8\\xE2\\x80\\xA9 ['
  end

  def test_remote_user_control_characters_are_escaped_when_hijacked
    log = hijack_log 'REMOTE_USER' => "alice\n"
    assert_single_line log
    assert_match %r{\A127\.0\.0\.1 - alice\\x0A \[.+\] "GET /path HTTP/1\.1" HIJACKED -1 \d+\.\d{4}\n\z}, log
  end

  def test_forwarded_for_control_characters_are_escaped
    log = request_log 'HTTP_X_FORWARDED_FOR' => "1.2.3.4\t5.6.7.8"
    assert_single_line log
    assert_match %r{\A1\.2\.3\.4\\x095\.6\.7\.8 - - \[.+\] "GET /path HTTP/1\.1" 200 5 \d+\.\d{4}\n\z}, log
  end

  def test_remote_user_utf8_text_is_logged_unchanged
    log = request_log 'REMOTE_USER' => 'José 日本'
    assert_single_line log
    assert_includes log, ' - José 日本 ['

    log = request_log 'REMOTE_USER' => 'José'.b
    assert_single_line log
    assert_includes log, ' - José ['
    assert_predicate log, :valid_encoding?
  end

  def test_remote_user_bytes_that_are_not_utf8_are_escaped
    log = request_log 'REMOTE_USER' => "Jos\xE9".b
    assert_single_line log
    assert_includes log, ' - Jos\\xE9 ['

    log = request_log 'REMOTE_USER' => "Jos\xC3"
    assert_single_line log
    assert_includes log, ' - Jos\\xC3 ['

    log = request_log 'REMOTE_USER' => "\x9B31m".b
    assert_single_line log
    assert_includes log, ' - \\x9B31m ['
    assert_predicate log, :valid_encoding?
  end

  def test_remote_user_absent_or_non_string
    log = request_log
    assert_single_line log
    assert_match %r{^127\.0\.0\.1 - - \[}, log

    log = request_log 'REMOTE_USER' => 42
    assert_single_line log
    assert_includes log, ' - 42 ['
  end
end
