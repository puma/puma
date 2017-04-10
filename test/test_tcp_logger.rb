require_relative "helper"

require "puma/events"
require "puma/tcp_logger"

class TestTCPLogger < Minitest::Test

  def setup
    @events = Puma::Events.new STDOUT, STDERR
    @server = Puma::Server.new nil, @events

    @server.app = proc { |env, socket|}
    @server.tcp_mode!

    @socket = nil
  end

  def test_events
    # in lib/puma/launcher.rb:85
    # Puma::Events is default tcp_logger for cluster mode
    logger = Puma::Events.new(STDOUT, STDERR)
    out, err = capture_subprocess_io do
      Puma::TCPLogger.new(logger, @server.app).call({}, @socket)
    end
    assert_match(/connected/, out)
    assert_equal('', err)
  end

  def test_io
    # in lib/puma/configuration.rb:184
    # STDOUT is default tcp_logger for single mode
    logger = STDOUT
    out, err = capture_subprocess_io do
      Puma::TCPLogger.new(logger, @server.app).call({}, @socket)
    end
    assert_match(/connected/, out)
    assert_equal('', err)
  end
end
