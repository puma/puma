require_relative "helper"
require_relative "helpers/integration"

class TestIntegrationPumactl < TestIntegration
  parallelize_me!

  def setup
    super

    @state_path   = "test/#{name}_puma.state"
    @control_path = "test/#{name}_control.sock"
  end

  def teardown
    super

    [@state_path, @control_path].each { |p| File.unlink(p) rescue nil }
  end

  def test_stop_tcp
    @control_tcp_port = UniquePort.call
    cli_server "-q test/rackup/sleep.ru --control-url tcp://#{HOST}:#{@control_tcp_port} --control-token #{TOKEN} -S #{@state_path}"

    cli_pumactl "stop"

    _, status = Process.wait2(@pid)
    assert_equal 0, status

    @server = nil
  end

  def test_stop_unix
    skip UNIX_SKT_MSG unless UNIX_SKT_EXIST
    cli_server "-q test/rackup/sleep.ru --control-url unix://#{@control_path} --control-token #{TOKEN} -S #{@state_path}", unix: true

    cli_pumactl "stop", unix: true

    _, status = Process.wait2(@pid)
    assert_equal 0, status

    @server = nil
  end

  def test_phased_restart_cluster
    skip NO_FORK_MSG unless HAS_FORK

    cli_server "-q -w #{WORKERS} test/rackup/sleep.ru --control-url unix://#{@control_path} --control-token #{TOKEN} -S #{@state_path}", unix: true

    s = UNIXSocket.new @bind_path
    @ios_to_close << s
    s << "GET /sleep5 HTTP/1.0\r\n\r\n"

    # Get the PIDs of the phase 0 workers.
    phase0_worker_pids = get_worker_pids 0
    assert File.exist? @bind_path

    # Phased restart
    cli_pumactl "phased-restart", unix: true

    # Get the PIDs of the phase 1 workers.
    phase1_worker_pids = get_worker_pids 1

    msg = "phase 0 pids #{phase0_worker_pids.inspect}  phase 1 pids #{phase1_worker_pids.inspect}"

    assert_equal WORKERS, phase0_worker_pids.length, msg
    assert_equal WORKERS, phase1_worker_pids.length, msg
    assert_empty phase0_worker_pids & phase1_worker_pids, "#{msg}\nBoth workers should be replaced with new"
    assert File.exist?(@bind_path), "Bind path must exist after phased restart"

    cli_pumactl "stop", unix: true

    _, status = Process.wait2(@pid)
    assert_equal 0, status

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

  private

  def cli_pumactl(argv, unix: false)
    if unix
      pumactl = IO.popen("#{BASE} bin/pumactl -C unix://#{@control_path} -T #{TOKEN} #{argv}", "r")
    else
      pumactl = IO.popen("#{BASE} bin/pumactl -C tcp://#{HOST}:#{@control_tcp_port} -T #{TOKEN} #{argv}", "r")
    end
    @ios_to_close << pumactl
    Process.wait pumactl.pid
    pumactl
  end
end
