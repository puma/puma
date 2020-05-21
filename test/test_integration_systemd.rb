require_relative "helper"
require_relative "helpers/integration"

require 'sd_notify'

class TestIntegrationSystemd < TestIntegration
  def setup
    skip "Skipped on Windows because it does not support Systemd" if windows?
    skip UNIX_SKT_MSG unless UNIX_SKT_EXIST

    ::Dir::Tmpname.create("puma_socket") do |sockaddr|
      @sockaddr = sockaddr
      @socket = Socket.new(:UNIX, :DGRAM, 0)
      socket_ai = Addrinfo.unix(sockaddr)
      @socket.bind(socket_ai)
      ENV["NOTIFY_SOCKET"] = sockaddr
    end

    ENV["SD_NOTIFY"] = "1"
  end

  def teardown
    return if skipped?
    @socket.close if @socket
    File.unlink(@sockaddr) if @sockaddr
    @socket = nil
    @sockaddr = nil
    ENV["SD_NOTIFY"] = nil
    ENV["NOTIFY_SOCKET"] = nil
  end

  def socket_message
    @socket.recvfrom(10)[0]
  end

  def test_notify_protocol
    skip "Skipped on Windows because it does not support Systemd" if windows?
    skip UNIX_SKT_MSG unless UNIX_SKT_EXIST

    count = SdNotify.ready
    assert_equal(socket_message, "READY=1")
    assert_equal(ENV["NOTIFY_SOCKET"], @sockaddr)
    assert_equal(count, 7)

    count = SdNotify.stopping
    assert_equal(socket_message, "STOPPING=1")
    assert_equal(ENV["NOTIFY_SOCKET"], @sockaddr)
    assert_equal(count, 10)

    refute SdNotify.watchdog?
  end

  def test_systemd_integration
    skip "Skipped on Windows because it does not support Systemd" if windows?
    skip UNIX_SKT_MSG unless UNIX_SKT_EXIST
    skip_unless_signal_exist? :TERM

    cli_server "test/rackup/hello.ru"
    assert_equal(socket_message, "READY=1")

    stop_server
    assert_match(socket_message, "STOPPING=1")
  end
end
