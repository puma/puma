# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/tmp_path"

require "puma/sd_notify"

class TestSdNotify < PumaTest
  include TmpPath

  def setup
    # JRuby and Windows both implement AF_UNIX for stream sockets only
    skip_if :jruby, :windows

    @sockaddr = tmp_path '.systemd'
    @socket = Socket.new(:UNIX, :DGRAM, 0)
    @socket.bind Addrinfo.unix(@sockaddr)
  end

  def teardown
    @socket&.close
    @socket = nil
    super
  end

  def test_ready_without_watchdog
    with_temp_env("NOTIFY_SOCKET" => @sockaddr, "WATCHDOG_USEC" => nil) do
      Puma::SdNotify.ready
    end

    assert_equal "READY=1", read_datagram
  end

  def test_ready_with_watchdog_sends_immediate_ping
    with_temp_env("NOTIFY_SOCKET" => @sockaddr, "WATCHDOG_USEC" => "60000000") do
      Puma::SdNotify.ready
    end

    assert_equal "READY=1\nWATCHDOG=1", read_datagram
  end

  def test_ready_with_watchdog_and_unset_env
    with_temp_env("NOTIFY_SOCKET" => @sockaddr, "WATCHDOG_USEC" => "60000000") do
      Puma::SdNotify.ready true

      refute ENV.key?("NOTIFY_SOCKET"), "ready(true) should unset NOTIFY_SOCKET"
    end

    assert_equal "READY=1\nWATCHDOG=1", read_datagram
  end

  private

  # systemd accepts several newline-separated pairs in one datagram, so read
  # the whole datagram rather than a fixed number of bytes
  def read_datagram
    assert @socket.wait_readable(1), "timed out waiting for a notification"
    @socket.sysread 1024
  end
end
