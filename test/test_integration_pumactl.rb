require_relative "helper"
require_relative "helpers/integration"

class TestIntegrationPumactl < TestIntegration
  include TmpPath
  parallelize_me!

  def workers ; 2 ; end

  def setup
    super

    @state_path   = tmp_path('.state')
    @control_path = tmp_path('.sock')
  end

  def teardown
    super

    refute File.exist?(@control_path), "Control path must be removed after stop"
  ensure
    [@state_path, @control_path].each { |p| File.unlink(p) rescue nil }
  end

  def test_stop_tcp
    skip_on :jruby, :truffleruby # Undiagnose thread race. TODO fix
    @control_tcp_port = UniquePort.call
    cli_server "-q test/rackup/sleep.ru --control-url tcp://#{HOST}:#{@control_tcp_port} --control-token #{TOKEN} -S #{@state_path}"

    cli_pumactl "stop"

    _, status = Process.wait2(@pid)
    assert_equal 0, status

    @server = nil
  end

  def test_stop_unix
    ctl_unix
  end

  def test_halt_unix
    ctl_unix 'halt'
  end

  def ctl_unix(signal='stop')
    skip UNIX_SKT_MSG unless UNIX_SKT_EXIST
    stderr = Tempfile.new(%w(stderr .log))
    cli_server "-q test/rackup/sleep.ru --control-url unix://#{@control_path} --control-token #{TOKEN} -S #{@state_path}",
      config: "stdout_redirect nil, '#{stderr.path}'",
      unix: true

    cli_pumactl signal, unix: true

    _, status = Process.wait2(@pid)
    assert_equal 0, status
    refute_match 'error', File.read(stderr.path)
    @server = nil
  end

  def test_phased_restart_cluster
    skip NO_FORK_MSG unless HAS_FORK
    cli_server "-q -w #{workers} test/rackup/sleep.ru --control-url unix://#{@control_path} --control-token #{TOKEN} -S #{@state_path}", unix: true

    start = Time.now

    s = UNIXSocket.new @bind_path
    @ios_to_close << s
    s << "GET /sleep1 HTTP/1.0\r\n\r\n"

    # Get the PIDs of the phase 0 workers.
    phase0_worker_pids = get_worker_pids 0
    assert File.exist? @bind_path

    # Phased restart
    cli_pumactl "phased-restart", unix: true

    # Get the PIDs of the phase 1 workers.
    phase1_worker_pids = get_worker_pids 1

    msg = "phase 0 pids #{phase0_worker_pids.inspect}  phase 1 pids #{phase1_worker_pids.inspect}"

    assert_equal workers, phase0_worker_pids.length, msg
    assert_equal workers, phase1_worker_pids.length, msg
    assert_empty phase0_worker_pids & phase1_worker_pids, "#{msg}\nBoth workers should be replaced with new"
    assert File.exist?(@bind_path), "Bind path must exist after phased restart"

    cli_pumactl "stop", unix: true

    _, status = Process.wait2(@pid)
    assert_equal 0, status
    assert_operator Time.now - start, :<, (DARWIN ? 8 : 5)
    @server = nil
  end

  def test_prune_bundler_with_multiple_workers
    skip NO_FORK_MSG unless HAS_FORK

    cli_server "-q -C test/config/prune_bundler_with_multiple_workers.rb --control-url unix://#{@control_path} --control-token #{TOKEN} -S #{@state_path}", unix: true

    s = UNIXSocket.new @bind_path
    @ios_to_close << s
    s << "GET / HTTP/1.0\r\n\r\n"

    body = s.read

    assert_match "200 OK", body
    assert_match "embedded app", body

    cli_pumactl "stop", unix: true

    _, status = Process.wait2(@pid)
    @server = nil
  end

  def test_kill_unknown
    skip_on :jruby

    # we run ls to get a 'safe' pid to pass off as puma in cli stop
    # do not want to accidentally kill a valid other process
    io = IO.popen(windows? ? "dir" : "ls")
    safe_pid = io.pid
    Process.wait safe_pid

    sout = StringIO.new

    e = assert_raises SystemExit do
      Puma::ControlCLI.new(%W!-p #{safe_pid} stop!, sout).run
    end
    sout.rewind
    # windows bad URI(is not URI?)
    assert_match(/No pid '\d+' found|bad URI\(is not URI\?\)/, sout.readlines.join(""))
    assert_equal(1, e.status)
  end
end
