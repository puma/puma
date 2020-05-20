require_relative "helper"
require_relative "helpers/integration"

require 'sd_notify'

class TestIntegrationSystemd < TestIntegration
  def setup
    ::Dir::Tmpname.create("puma_socket") do |sockaddr|
      @sockaddr = sockaddr
      @socket = Socket.new(:UNIX, :DGRAM, 0)
      socket_ai = Addrinfo.unix(sockaddr)
      @socket.bind(socket_ai)
      ENV["NOTIFY_SOCKET"] = sockaddr
    end
  end

  def teardown
    @socket.close if @socket
    File.unlink(@sockaddr) if @sockaddr
    @socket = nil
    @sockaddr = nil
  end

  def socket_message
    @socket.recvfrom(10)[0]
  end

  def test_notify_protocol
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
    skip_unless_signal_exist? :TERM

    cli_server "test/rackup/hello.ru"
    assert_equal(socket_message, "READY=1")

    stop_server
    assert_match(socket_message, "STOPPING=1")
  end
end
