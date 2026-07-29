# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/integration"

class TestPluginSystemd < TestIntegration
  parallelize_me! if ::Puma::IS_MRI

  THREAD_LOG = TRUFFLE ? "{ 0/16 threads, 16 available, 0 backlog }" :
    "{ 0/5 threads, 5 available, 0 backlog }"

  def setup
    skip_unless :linux
    skip_if :jruby

    super

    @sockaddr = tmp_path '.systemd'
    @socket = Socket.new(:UNIX, :DGRAM, 0)
    @socket.bind Addrinfo.unix(@sockaddr)
    @env = { "NOTIFY_SOCKET" => @sockaddr }
    @messages = []
  end

  def teardown
    return if skipped?
    @socket&.close
    @socket = nil
    super
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
    wd_env = @env.merge({"WATCHDOG_USEC" => "1_000_000"})
    cli_server "test/rackup/hello.ru", env: wd_env
    assert_message "READY=1"

    assert_message "WATCHDOG=1"

    stop_server
    assert_message "STOPPING=1"
  end

  def test_systemd_watchdog_sends_immediate_ping_after_ready
    # the watchdog loop pings every WATCHDOG_USEC/2, so a 60 second interval
    # rules the periodic loop out as the source of this WATCHDOG=1
    wd_env = @env.merge({"WATCHDOG_USEC" => "60_000_000"})
    cli_server "test/rackup/hello.ru", env: wd_env

    assert_message "READY=1"
    assert_message "WATCHDOG=1"

    stop_server
    assert_message "STOPPING=1"
  end

  def test_systemd_notify
    cli_server "test/rackup/hello.ru", env: @env
    assert_message "READY=1"

    assert_message "STATUS=Puma #{Puma::Const::VERSION}: worker: #{THREAD_LOG}"

    stop_server
    assert_message "STOPPING=1"
  end

  def test_systemd_cluster_notify
    skip_unless :fork
    cli_server "-w2 test/rackup/hello.ru", env: @env
    assert_message "READY=1"

    assert_message(
      "STATUS=Puma #{Puma::Const::VERSION}: cluster: 2/2, worker_status: [#{THREAD_LOG},#{THREAD_LOG}]")

    stop_server
    assert_message "STOPPING=1"
  end

  private

  def assert_restarts_with_systemd(signal, workers: 2)
    skip_unless(:fork) unless workers.zero?
    cli_server "test/rackup/hello.ru", env: @env, config: <<~CONFIG
      workers #{workers}
      #{"preload_app! false" if signal == :USR1}
    CONFIG
    get_worker_pids(0, workers) if workers == 2
    assert_message 'READY=1'

    phase_ary = signal == :USR1 ? [1,2] : [0,0]

    Process.kill signal, @pid
    get_worker_pids(phase_ary[0], workers) if workers == 2
    assert_message 'RELOADING=1'
    assert_message 'READY=1'

    Process.kill signal, @pid
    get_worker_pids(phase_ary[1], workers) if workers == 2
    assert_message 'RELOADING=1'
    assert_message 'READY=1'

    stop_server
    assert_message 'STOPPING=1'
  end

  # Read whole datagrams, since a single datagram may carry several
  # newline-separated messages, eg "READY=1\nWATCHDOG=1". Reading fewer bytes
  # than the datagram holds discards the remainder.
  def assert_message(msg)
    drop_status = !msg.start_with?('STATUS=')

    loop do
      # the plugin's status loop interleaves STATUS= messages every second
      @messages.shift while drop_status && @messages.first&.start_with?('STATUS=')
      break if @messages.any?
      break unless @socket.wait_readable 1
      @messages.concat @socket.sysread(1_024).split("\n")
    end

    assert_equal msg, @messages.shift
  end
end
