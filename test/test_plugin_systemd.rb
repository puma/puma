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
    @message = +''
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

  def test_systemd_notify
    cli_server "test/rackup/hello.ru", env: @env
    assert_message "READY=1"

    assert_message "STATUS=Puma #{Puma::Const::VERSION}: worker: #{THREAD_LOG}"

    stop_server
    assert_message "STOPPING=1"
  end

  # A `fork_worker` refork respawns worker 0 from its already-booted template;
  # it does not reload the app, so it must not flip systemd's Active status
  # to "reloading" (nothing tells it "ready" again afterwards, which would
  # leave the status stuck — see #3273).
  def test_systemd_no_reloading_notify_on_refork
    skip_unless :fork
    refork = Tempfile.new 'refork'
    wrkrs = 2
    cli_server "-w #{wrkrs} test/rackup/hello_with_delay.ru", env: @env, config: <<~CONFIG
      fork_worker 20
      before_refork { File.write '#{refork.path}', 'Reforked' }
    CONFIG
    assert_message 'READY=1'

    socks = []
    until refork.read == 'Reforked'
      socks << fast_connect
      sleep 0.004
    end
    100.times {
      socks << fast_connect
      sleep 0.004
    }
    socks.each { |s| read_body s }

    # Drain whatever the notify socket received during the refork window
    # (periodic STATUS= updates are expected) and confirm RELOADING=1 is
    # not among them.
    received = +''
    received << @socket.sysread(4096) while @socket.wait_readable(0.2)
    refute_includes received, 'RELOADING=1'

    stop_server
    assert_message 'STOPPING=1'
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

  def assert_message(msg)
    @socket.wait_readable 1
    @message << @socket.sysread(msg.bytesize)
    # below is kind of hacky, but seems to work correctly when slow CI systems
    # write partial status messages
    if @message.start_with?('STATUS=') && !msg.start_with?('STATUS=')
      @message << @socket.sysread(512) while @socket.wait_readable(1) && !@message.include?(msg)
      assert_includes @message, msg
      @message = @message.split(msg, 2).last
    else
      assert_equal msg, @message
      @message = +''
    end
  end
end
