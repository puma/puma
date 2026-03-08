# frozen_string_literal: true

require "puma/events"

require_relative "helper"
require_relative "helpers/test_puma"
require_relative "helpers/test_puma/puma_socket"
require_relative "helpers/test_puma/shutdown_requests"

class TestPumaServerShutdownDebug < PumaTest
  include TestPuma
  include TestPuma::PumaSocket
  include TestPuma::ShutdownRequests

  HOST = HOST4

  def setup
    @host = HOST
    @app = ->(env) { [200, {}, [env["rack.url_scheme"]]] }

    @log_writer = Puma::LogWriter.strings
    @events = Puma::Events.new
    @server = Puma::Server.new(@app, @events, { log_writer: @log_writer })
  end

  def teardown
    @server.stop(true)
  end

  def test_shutdown_with_shutdown_debug
    output = capture_syswrite do
      shutdown_requests(s1_response: /204/, s2_response: /204/, shutdown_debug: true)
    end

    assert_equal 1, output.scan("Shutdown initiated").length
    assert_equal 1, output.scan("Begin thread backtrace dump").length
  end

  def test_shutdown_with_shutdown_debug_on_force
    output = capture_syswrite do
      shutdown_requests(s1_response: /204/, s2_response: /204/, shutdown_debug: :on_force)
    end

    assert_empty output
  end

  def test_force_shutdown_with_shutdown_debug
    mutex = Mutex.new
    app_started = ConditionVariable.new

    server_run(shutdown_debug: true, force_shutdown_after: 0) { |env|
      mutex.synchronize { app_started.signal }
      sleep 60
      [204, {}, []]
    }

    output = capture_syswrite do
      mutex.synchronize do
        send_http("GET / HTTP/1.1\r\n\r\n")
        app_started.wait(mutex)
      end
      @server.stop(true)
    end

    assert_equal 1, output.scan("Shutdown initiated").length
    assert_equal 1, output.scan("Begin thread backtrace dump").length
  end

  def test_force_shutdown_with_shutdown_debug_on_force
    mutex = Mutex.new
    app_started = ConditionVariable.new

    server_run(shutdown_debug: :on_force, force_shutdown_after: 0, pool_shutdown_grace_time: 0) { |env|
      mutex.synchronize { app_started.signal }
      sleep 60
      [204, {}, []]
    }

    output = capture_syswrite do
      mutex.synchronize do
        send_http("GET / HTTP/1.1\r\n\r\n")
        app_started.wait(mutex)
      end
      @server.stop(true)
    end

    assert_equal 1, output.scan("Shutdown timeout exceeded").length
    assert_equal 1, output.scan("Shutdown grace timeout exceeded").length
    assert_equal 2, output.scan("Begin thread backtrace dump").length
  end

  private

  def capture_syswrite
    calls = []
    $stdout.stub :syswrite, ->(msg) { calls << msg; msg.bytesize } do
      yield
    end
    calls.join
  end

  def server_run(**options, &block)
    options[:log_writer] ||= @log_writer
    options[:min_threads] ||= 1
    @server = Puma::Server.new(block || @app, @events, options)
    @bind_port = @server.add_tcp_listener(@host, 0).addr[1]
    @server.run
  end
end
