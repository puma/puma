# frozen_string_literal: true

require_relative 'helper'
require_relative 'helpers/test_puma/server_in_process'

class TestLogWriter < TestPuma::ServerInProcess
  def test_null
    log_writer = Puma::LogWriter.null

    assert_instance_of Puma::NullIO, log_writer.stdout
    assert_instance_of Puma::NullIO, log_writer.stderr
    assert_equal log_writer.stdout, log_writer.stderr
  end

  def test_strings
    log_writer = Puma::LogWriter.strings

    assert_instance_of StringIO, log_writer.stdout
    assert_instance_of StringIO, log_writer.stderr
  end

  def test_stdio
    log_writer = Puma::LogWriter.stdio

    assert_equal STDOUT, log_writer.stdout
    assert_equal STDERR, log_writer.stderr
  end

  def test_stdio_respects_sync
    log_writer = Puma::LogWriter.stdio

    assert_equal STDOUT.sync, log_writer.stdout.sync
    assert_equal STDERR.sync, log_writer.stderr.sync
    assert_equal STDOUT, log_writer.stdout
    assert_equal STDERR, log_writer.stderr
  end

  def test_log_writes_to_stdout
    out, _ = capture_io do
      Puma::LogWriter.stdio.log("ready")
    end

    assert_equal "ready\n", out
  end

  def test_null_log_does_nothing
    out, _ = capture_io do
      Puma::LogWriter.null.log("ready")
    end

    assert_equal "", out
  end

  def test_write_writes_to_stdout
    out, _ = capture_io do
      Puma::LogWriter.stdio.write("ready")
    end

    assert_equal "ready", out
  end

  def test_debug_writes_to_stdout_if_env_is_present
    original_debug, ENV["PUMA_DEBUG"] = ENV["PUMA_DEBUG"], "1"

    out, _ = capture_io do
      Puma::LogWriter.stdio.debug("ready")
    end

    assert_equal "% ready\n", out
  ensure
    ENV["PUMA_DEBUG"] = original_debug
  end

  def test_debug_not_write_to_stdout_if_env_is_not_present
    out, _ = capture_io do
      Puma::LogWriter.stdio.debug("ready")
    end

    assert_empty out
  end

  def test_error_writes_to_stderr_and_exits
    did_exit = false

    _, err = capture_io do
      begin
        Puma::LogWriter.stdio.error("interrupted")
      rescue SystemExit
        did_exit = true
      ensure
        assert did_exit
      end
    end

    assert_includes err, "ERROR: interrupted"
  end

  def test_pid_formatter
    pid = Process.pid

    out, _ = capture_io do
      log_writer = Puma::LogWriter.stdio

      log_writer.formatter = Puma::LogWriter::PidFormatter.new

      log_writer.write("ready")
    end

    assert_equal "[#{ pid }] ready", out
  end

  def test_custom_log_formatter
    custom_formatter = proc { |str| "-> #{ str }" }

    out, _ = capture_io do
      log_writer = Puma::LogWriter.stdio

      log_writer.formatter = custom_formatter

      log_writer.write("ready")
    end

    assert_equal "-> ready", out
  end

  def test_parse_error
    server_run app: ->(_) { [200, {"Content-Type" => "plain/text"}, ["hello\n"]] }

    path = "/"
    params = "a"*1024*10

    req = "GET #{path}?a=#{params} HTTP/1.1\r\nConnection: close\r\n\r\n"

    send_http_read_response req
    sleep 0.01 # intermittent non MRI errors with empty stderr
    err_log = @log_writer.stderr.string

    assert_includes err_log, "HTTP parse error, malformed request"
    assert_includes err_log, "(\"GET #{path}\" - (-))"
  end

  # test_puma_server_ssl.rb checks that ssl errors are raised correctly,
  # but it mocks the actual error code.  This tests the code, but it will
  # break if the logged message changes
  def ssl_error(addr, subj)
    log_writer = Puma::LogWriter.strings

    # variable shadowed error on older Rubies
    ssl_mock = -> (addr1, subj1) {
      obj = Object.new
      obj.define_singleton_method(:peeraddr) { addr1 }
      if subj
        cert = Object.new
        cert.define_singleton_method(:subject) { subj1 }
        obj.define_singleton_method(:peercert) { cert }
      else
        obj.define_singleton_method(:peercert) { nil }
      end
      obj
    }

    log_writer.ssl_error OpenSSL::SSL::SSLError, ssl_mock.call(addr, subj)
    log_writer.stderr.string
  end

  def test_ssl_error_addr_subj
    error = ssl_error ['127.0.0.1'], 'test_cert'
    assert_includes error, "SSL error"
    assert_includes error, "peer: 127.0.0.1"
    assert_includes error, "cert: test_cert"
  end if ::Puma::HAS_SSL

  def test_ssl_error_no_addr_no_subj
    error = ssl_error nil, nil
    assert_includes error, "SSL error"
    assert_includes error, "peer: <unknown>"
    assert_includes error, "cert: :"
  end if ::Puma::HAS_SSL
end
