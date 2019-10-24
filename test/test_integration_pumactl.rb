require_relative "helper"
require_relative "helpers/integration"

class TestIntegrationPumactl < TestIntegration
  parallelize_me! unless Puma.jruby?

  def test_stop_tcp_single
    setup_puma bind: :tcp, ctrl: :tcp

    cli_server "-q test/rackup/sleep.ru"

    stop_server_goodbye

    begin # rescue needed on Windows?
      _, status = Process.wait2 @pid
      assert_equal 0, status
    rescue Errno::ECHILD
    end
  end

  def test_halt_tcp_single
    setup_puma bind: :tcp, ctrl: :tcp

    cli_server "-q test/rackup/sleep.ru"

    run_pumactl 'halt'
    assert_io 'Stopping immediately!'

    begin # rescue needed on Windows?
      _, status = Process.wait2 @pid
      assert_equal 0, status
    rescue Errno::ECHILD
    end
  end

  def test_stop_unix_single
    skip UNIX_SKT_MSG unless HAS_UNIX
    setup_puma bind: :tcp, ctrl: :unix
    cli_server "-q test/rackup/sleep.ru"

    stop_server_goodbye

    _, status = Process.wait2 @pid
    assert_equal 0, status
  end

  def test_halt_unix_single
    skip UNIX_SKT_MSG unless HAS_UNIX
    setup_puma bind: :tcp, ctrl: :unix
    cli_server "-q test/rackup/sleep.ru"

    run_pumactl 'halt'
    assert_io 'Stopping immediately!'

    _, status = Process.wait2 @pid
    assert_equal 0, status
  end

  def test_stop_unix_cluster
    skip UNIX_SKT_MSG unless HAS_UNIX
    skip NO_FORK_MSG unless HAS_FORK
    setup_puma bind: :tcp, ctrl: :unix
    cli_server "-q -w #{WORKERS} test/rackup/sleep.ru"

    stop_server_wait
  end

  def test_halt_unix_cluster
    skip UNIX_SKT_MSG unless HAS_UNIX
    skip NO_FORK_MSG unless HAS_FORK
    setup_puma bind: :tcp, ctrl: :unix
    cli_server "-q -w #{WORKERS} test/rackup/sleep.ru"

    run_pumactl 'halt'
    assert_io 'Stopping immediately!'
  end

  def test_phased_restart_cluster
    skip NO_FORK_MSG unless HAS_FORK
    setup_puma bind: :unix, ctrl: :unix

    cli_server "-q -w #{WORKERS} test/rackup/sleep.ru"

    connect 'sleep5'

    # Get the PIDs of the phase 0 workers.
    phase0_worker_pids = get_worker_pids 0
    assert File.exist? @path_bind

    # Phased restart
    run_pumactl 'phased-restart'

    # Get the PIDs of the phase 1 workers.
    phase1_worker_pids = get_worker_pids 1

    msg = "phase 0 pids #{phase0_worker_pids.inspect}  phase 1 pids #{phase1_worker_pids.inspect}"

    assert_equal WORKERS, phase0_worker_pids.length, msg
    assert_equal WORKERS, phase1_worker_pids.length, msg
    assert_empty phase0_worker_pids & phase1_worker_pids, "#{msg}\nBoth workers should be replaced with new"
    assert File.exist?(@path_bind), "Bind path must exist after phased restart"

    run_pumactl 'stop'

    _, status = Process.wait2 @pid
    assert_equal 0, status

    @server = nil
  end

  def test_kill_unknown
    skip_on :jruby

    # we run ls to get a 'safe' pid to pass off as puma in cli stop
    # do not want to accidentally kill a valid other process
    io = IO.popen(windows? ? 'dir' : 'ls')
    safe_pid = io.pid
    Process.wait safe_pid

    sout = StringIO.new

    e = assert_raises SystemExit do
      Puma::ControlCLI.new(%W!-p #{safe_pid} stop!, sout).run
    end
    sout.rewind
    # windows bad URI(is not URI?)
    assert_match(/No pid '\d+' found|bad URI\(is not URI\?\)/, sout.readlines.join(""))
    assert_equal 1, e.status
  end
end
