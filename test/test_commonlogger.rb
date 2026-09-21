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
end
