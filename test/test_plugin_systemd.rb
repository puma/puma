require_relative "helper"
require_relative "helpers/integration"

class TestPluginSystemd < TestIntegration
  parallelize_me! if ::Puma.mri?

  THREAD_LOG = TRUFFLE ? "{ 0/16 threads, 16 available, 0 backlog }" :
    "{ 0/5 threads, 5 available, 0 backlog }"

  def setup
    skip_unless :linux
    skip_unless :unix
    skip_unless_signal_exist? :TERM
    skip_if :jruby

    super

    ::Dir::Tmpname.create("puma_socket") do |sockaddr|
      @sockaddr = sockaddr
      @socket = Socket.new(:UNIX, :DGRAM, 0)
      socket_ai = Addrinfo.unix(sockaddr)
      @socket.bind(socket_ai)
      @env = {"NOTIFY_SOCKET" => sockaddr }
    end
  end

  def teardown
    return if skipped?
    @socket&.close
    File.unlink(@sockaddr) if @sockaddr
    @socket = nil
    @sockaddr = nil
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
    assert_includes @socket.recvfrom(15)[0], "STOPPING=1"
  end

  def test_systemd_notify
    cli_server "test/rackup/hello.ru", env: @env
    assert_message "READY=1"

    assert_message "STATUS=Puma #{Puma::Const::VERSION}: worker: #{THREAD_LOG}"

    stop_server
    assert_message "STOPPING=1"
  end

  def test_systemd_extend_timeout_notify
    notify_env = @env.merge({"EXTEND_TIMEOUT_USEC" => "1_000_001"})
    cli_server "test/rackup/hello.ru", env: notify_env
    assert_message "EXTEND_TIMEOUT_USEC=1000001"

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
    cli_server "-w#{workers} test/rackup/hello.ru", env: @env
    assert_message 'READY=1'

    Process.kill signal, @pid
    connect.write "GET / HTTP/1.1\r\n\r\n"
    assert_message 'RELOADING=1'
    assert_message 'READY=1'

    Process.kill signal, @pid
    connect.write "GET / HTTP/1.1\r\n\r\n"
    assert_message 'RELOADING=1'
    assert_message 'READY=1'

    stop_server
    assert_message 'STOPPING=1'
  end

  def assert_message(msg)
    @socket.wait_readable 1
    assert_equal msg, @socket.recvfrom(msg.bytesize)[0]
  end
end
