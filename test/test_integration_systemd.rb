require_relative "helper"
require_relative "helpers/integration"

require 'sd_notify'

class TestIntegrationSystemd < TestIntegration
  def setup
    skip "Skipped because Systemd support is linux-only" if windows? || osx?
    skip UNIX_SKT_MSG unless UNIX_SKT_EXIST
    skip_unless_signal_exist? :TERM
    skip_on :jruby

    super

    ::Dir::Tmpname.create("puma_socket") do |sockaddr|
      @sockaddr = sockaddr
      @socket = Socket.new(:UNIX, :DGRAM, 0)
      socket_ai = Addrinfo.unix(sockaddr)
      @socket.bind(socket_ai)
      ENV["NOTIFY_SOCKET"] = sockaddr
    end
  end

  def teardown
    return if skipped?
    @socket.close if @socket
    File.unlink(@sockaddr) if @sockaddr
    @socket = nil
    @sockaddr = nil
    ENV["NOTIFY_SOCKET"] = nil
    ENV["WATCHDOG_USEC"] = nil
  end

  def socket_message
    @socket.recvfrom(15)[0]
  end

  def test_systemd_integration
    cli_server "test/rackup/hello.ru"
    assert_equal(socket_message, "READY=1")

    connection = connect
    restart_server connection
    assert_equal(socket_message, "RELOADING=1")
    assert_equal(socket_message, "READY=1")

    stop_server
    assert_equal(socket_message, "STOPPING=1")
  end

  def test_systemd_watchdog
    ENV["WATCHDOG_USEC"] = "1_000_000"

    cli_server "test/rackup/hello.ru"
    assert_equal(socket_message, "READY=1")

    assert_equal(socket_message, "WATCHDOG=1")

    stop_server
    assert_match(socket_message, "STOPPING=1")
  end
end
