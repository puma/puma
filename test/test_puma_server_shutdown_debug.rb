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
    @server = Puma::Server.new @app, @events, { log_writer: @log_writer }
  end

  def teardown
    @server.stop true
  end

  def test_shutdown_with_shutdown_debug
    calls = []

    $stdout.stub :syswrite, ->(msg) { calls << msg; msg.bytesize } do
      shutdown_requests(s1_response: /204/, s2_response: /204/, shutdown_debug: true)
    end

    output = calls.join
    assert_equal 1, output.scan("Shutdown initiated").length
    assert_equal 1, output.scan("Begin thread backtrace dump").length
  end

  def test_force_shutdown_with_shutdown_debug
    calls = []

    $stdout.stub :syswrite, ->(msg) { calls << msg; msg.bytesize } do
      shutdown_requests(s1_complete: false, s1_response: /503/, shutdown_debug: true, force_shutdown_after: 0)
    end

    output = calls.join
    assert_equal 1, output.scan("Shutdown initiated").length
    assert_equal 1, output.scan("Begin thread backtrace dump").length
  end

  def test_shutdown_with_shutdown_debug_on_force
    calls = []

    $stdout.stub :syswrite, ->(msg) { calls << msg; msg.bytesize } do
      shutdown_requests(s1_response: /204/, s2_response: /204/, shutdown_debug: :on_force)
    end

    output = calls.join
    assert_equal 0, output.scan("Begin thread backtrace dump").length
  end

  def test_force_shutdown_with_shutdown_debug_on_force
    calls = []

    Puma::ThreadPool.stub_const(:SHUTDOWN_GRACE_TIME, 0) do
      $stdout.stub :syswrite, ->(msg) { calls << msg; msg.bytesize } do
        shutdown_requests(s1_complete: false, s1_response: /503/, shutdown_debug: :on_force, force_shutdown_after: 0)
      end
    end

    output = calls.join
    assert_equal 1, output.scan("Shutdown timeout exceeded").length
    assert_equal 1, output.scan("Shutdown grace timeout exceeded").length
    assert_equal 2, output.scan("Begin thread backtrace dump").length
  end

  private

  def server_run(**options, &block)
    options[:log_writer]  ||= @log_writer
    options[:min_threads] ||= 1
    @server = Puma::Server.new block || @app, @events, options
    @bind_port = (@server.add_tcp_listener @host, 0).addr[1]
    @server.run
  end
end
