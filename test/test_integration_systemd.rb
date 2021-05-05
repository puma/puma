require_relative "helper"
require_relative "helpers/integration"

require 'sd_notify'

class TestIntegrationSystemd < TestIntegration
  def setup
    skip "Skipped because Systemd support is linux-only" if windows? || osx?
    skip_unless :unix
    skip_unless_signal_exist? :TERM
    skip_if :jruby

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

  def test_systemd_notify_usr1_phased_restart_cluster
    skip_unless :fork
    assert_restarts_with_systemd :USR1
  end

  def test_systemd_notify_usr2_hot_restart_cluster
    skip_unless :fork
    assert_restarts_with_systemd :USR2
  end

  def test_systemd_notify_usr2_hot_restart_single
    assert_restarts_with_systemd :USR2, workers: 0
  end

  def test_systemd_watchdog
    ENV["WATCHDOG_USEC"] = "1_000_000"

    cli_server "test/rackup/hello.ru"
    assert_equal(socket_message, "READY=1")

    assert_equal(socket_message, "WATCHDOG=1")

    stop_server
    assert_match(socket_message, "STOPPING=1")
  end

  private

  def assert_restarts_with_systemd(signal, workers: 2)
    cli_server "-w#{workers} test/rackup/hello.ru"
    assert_equal socket_message, 'READY=1'

    Process.kill signal, @pid
    connect.write "GET / HTTP/1.1\r\n\r\n"
    assert_equal socket_message, 'RELOADING=1'
    assert_equal socket_message, 'READY=1'

    Process.kill signal, @pid
    connect.write "GET / HTTP/1.1\r\n\r\n"
    assert_equal socket_message, 'RELOADING=1'
    assert_equal socket_message, 'READY=1'

    stop_server
    assert_equal socket_message, 'STOPPING=1'
  end

  def socket_message
    @socket.recvfrom(15)[0]
  end
end
