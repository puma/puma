# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/test_puma/server_spawn"

class TestPluginSystemd < TestPuma::ServerSpawn
  parallelize_me! if ::Puma::IS_MRI

  THREAD_LOG = TRUFFLE ? "{ 0/16 threads, 16 available, 0 backlog }" :
    "{ 0/5 threads, 5 available, 0 backlog }"

  STATUS_SINGLE  = "STATUS=Puma #{Puma::Const::VERSION}: worker: #{THREAD_LOG}"

  STATUS_CLUSTER = "STATUS=Puma #{Puma::Const::VERSION}: cluster: 2/2," \
    " worker_status: [#{THREAD_LOG},#{THREAD_LOG}]"

  def setup
    skip_unless :linux
    skip_unless :unix
    skip_unless_signal_exist? :TERM
    skip_if :jruby

    @workers = 0

    sockaddr = unique_path %w[systemd .puma]
    @socket = Socket.new(:UNIX, :DGRAM, 0)
    socket_ai = Addrinfo.unix(sockaddr)
    @socket.bind(socket_ai)
    @env = {"NOTIFY_SOCKET" => sockaddr }
    @ios_to_close << @socket
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
    server_spawn "test/rackup/hello.ru", env: wd_env
    assert_message "READY=1"

    assert_message "WATCHDOG=1"

    stop_server
    assert_message "STOPPING=1"
  end

  def test_systemd_notify
    server_spawn "test/rackup/hello.ru", env: @env
    assert_message "READY=1"

    assert_message STATUS_SINGLE

    stop_server
    assert_message "STOPPING=1"
  end

  def test_systemd_cluster_notify
    skip_unless :fork
    @workers = 2
    server_spawn "-w2 test/rackup/hello.ru", env: @env
    assert_message "READY=1"

    assert_message STATUS_CLUSTER

    stop_server
    assert_message "STOPPING=1"
  end

  private

  def assert_restarts_with_systemd(signal, workers: 2)
    skip_unless(:fork) unless workers.zero?
    status = workers == 2 ? STATUS_CLUSTER : STATUS_SINGLE
    @workers = workers
    server_spawn "-w#{workers} test/rackup/hello.ru", env: @env
    assert_message 'READY=1'

    assert_message status

    Process.kill signal, @pid

    assert_message 'RELOADING=1'
    assert_message 'READY=1'

    Process.kill signal, @pid

    assert_message 'RELOADING=1'
    assert_message 'READY=1'

    assert_message status

    stop_server
    assert_message 'STOPPING=1'
  end

  def assert_message(msg)
    status = @workers.zero? ? STATUS_SINGLE : STATUS_CLUSTER
    msg_size = msg.bytesize

    @socket.wait_readable 2
    data = @socket.recvfrom(msg_size)[0]

    while data.start_with?('STATUS=') && msg != status
      # additional status messages may be sent
      remaining = status.bytesize - msg_size
      @socket.recvfrom(remaining)
      data = @socket.recvfrom(msg_size)[0]
    end
    assert_equal msg, data
  end
end
