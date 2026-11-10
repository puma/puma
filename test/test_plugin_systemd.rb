# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/integration"
require "puma/plugin"
require "puma/sd_notify"

class TestPluginSystemd < TestIntegration

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

  def test_systemd_extend_timeout_notify
    notify_env = @env.merge({
      "EXTEND_TIMEOUT_USEC" => "300_000",
      "EXTEND_TIMEOUT_MAX_USEC" => "400_000"
    })
    cli_server "test/rackup/boot_delay.ru", env: notify_env
    first_timeout = assert_extend_timeout_usec(read_message, 300_000)
    second_timeout = assert_extend_timeout_usec(read_message)
    assert_operator second_timeout, :<=, 100_000
    assert_operator first_timeout + second_timeout, :<=, 400_000

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

  def read_message
    @socket.wait_readable 1
    @socket.sysread(512)
  end

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
    # a hot restart execs the process, so allow it the same time to report as
    # the wait_for_server_to_* helpers allow a boot
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + LOG_TIMEOUT

    loop do
      # the plugin's status loop interleaves STATUS= messages every second
      @messages.shift while drop_status && @messages.first&.start_with?('STATUS=')
      break if @messages.any?
      wait = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      break if wait <= 0
      break unless @socket.wait_readable wait
      @messages.concat @socket.sysread(512).split("\n")
    end

    assert_equal msg, @messages.shift
  end
end

class TestPluginSystemdUnit < PumaTest
  def setup
    @original_plugins = Puma::Plugins.instance_variable_get(:@plugins)
    @original_background = Puma::Plugins.instance_variable_get(:@background)
    @systemd_feature_loaded = $LOADED_FEATURES.any? do |path|
      path.end_with?("puma/plugin/systemd.rb")
    end

    Puma::Plugins.instance_variable_set(:@plugins, @original_plugins.dup)
    Puma::Plugins.instance_variable_set(:@background, @original_background.dup)

    require "puma/plugin/systemd"

    @plugin = Puma::Plugins.find("systemd").new
  end

  def teardown
    Puma::Plugins.instance_variable_set(:@plugins, @original_plugins)
    Puma::Plugins.instance_variable_set(:@background, @original_background)
    unless @systemd_feature_loaded
      $LOADED_FEATURES.delete_if { |path| path.end_with?("puma/plugin/systemd.rb") }
    end
    super
  end

  def test_extend_timeout_sleep_time_subtracts_buffer
    sleep_time = @plugin.send(:extend_timeout_sleep_time, 10_000_000)
    assert_equal 5.0, sleep_time
  end

  def test_extend_timeout_sleep_time_uses_interval_when_short
    sleep_time = @plugin.send(:extend_timeout_sleep_time, 4_000_000)
    assert_equal 4.0, sleep_time
  end
end

class TestSdNotify < PumaTest
  def test_extend_timeout_usec_defaults_to_zero
    with_env("EXTEND_TIMEOUT_USEC" => "100") do
      assert_equal 100, Puma::SdNotify.extend_timeout_usec
    end

    with_env("EXTEND_TIMEOUT_USEC" => nil) do
      assert_equal 0, Puma::SdNotify.extend_timeout_usec
    end
  end

  def test_extend_timeout_usec_invalid
    with_env("EXTEND_TIMEOUT_USEC" => "nope") do
      assert_equal 0, Puma::SdNotify.extend_timeout_usec
    end
  end

  def test_extend_timeout_max_usec_defaults_to_extend_timeout_usec
    with_env("EXTEND_TIMEOUT_USEC" => "120", "EXTEND_TIMEOUT_MAX_USEC" => nil) do
      assert_equal 120, Puma::SdNotify.extend_timeout_max_usec
    end
  end

  def test_extend_timeout_max_usec_invalid
    with_env("EXTEND_TIMEOUT_USEC" => "120", "EXTEND_TIMEOUT_MAX_USEC" => "bad") do
      assert_equal 0, Puma::SdNotify.extend_timeout_max_usec
    end
  end

  def test_extend_timeout_predicate
    with_env("EXTEND_TIMEOUT_USEC" => "90") do
      assert Puma::SdNotify.extend_timeout?
    end

    with_env("EXTEND_TIMEOUT_USEC" => nil) do
      refute Puma::SdNotify.extend_timeout?
    end
  end

  private

  def with_env(values)
    original = {}

    values.each do |key, value|
      original[key] = ENV.key?(key) ? ENV[key] : :__undefined__

      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end

    yield
  ensure
    original.each do |key, value|
      if value == :__undefined__
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end
end
