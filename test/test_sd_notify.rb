# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/tmp_path"
require_relative "../lib/puma/sd_notify"

class TestSdNotify < PumaTest
  include TmpPath

  def setup
    super

    @sockaddr = tmp_path '.sd_notify'
    @socket = Socket.new(:UNIX, :DGRAM, 0)
    @socket.bind Addrinfo.unix(@sockaddr)
    @message = +''
  end

  def teardown
    @socket&.close
    @socket = nil

    super
  end

  def test_ready_with_watchdog_unsets_env_after_watchdog
    with_temp_env("NOTIFY_SOCKET" => @sockaddr, "WATCHDOG_USEC" => "10_000_000") do
      Puma::SdNotify.ready(true)

      assert_message "READY=1"
      assert_message "WATCHDOG=1"
      refute ENV.key?("NOTIFY_SOCKET")
    end
  end

  private

  def assert_message(msg)
    @socket.wait_readable 1
    @message << @socket.sysread(msg.bytesize)
    assert_equal msg, @message
    @message = +''
  end
end
