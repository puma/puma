require_relative "helper"
require_relative "helpers/integration"

class TestIntegrationPumactl < TestIntegration
  include TmpPath
  parallelize_me! if ::Puma.mri?

  def workers ; 2 ; end

  def setup
    super
    @control_path = nil
    @state_path = tmp_path('.state')
  end

  def teardown
    super

    refute @control_path && File.exist?(@control_path), "Control path must be removed after stop"
  ensure
    [@state_path, @control_path].each { |p| File.unlink(p) rescue nil }
  end

  def test_stop_tcp
    skip_if :jruby, :truffleruby # Undiagnose thread race. TODO fix
    @control_tcp_port = UniquePort.call
    cli_server "-q test/rackup/sleep.ru #{set_pumactl_args} -S #{@state_path}"

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
    skip_unless :unix
    stderr = Tempfile.new(%w(stderr .log))

    cli_server "-q test/rackup/sleep.ru #{set_pumactl_args unix: true} -S #{@state_path}",
      config: "stdout_redirect nil, '#{stderr.path}'",
      unix: true

    cli_pumactl signal, unix: true

    _, status = Process.wait2(@pid)
    assert_equal 0, status
    refute_match 'error', File.read(stderr.path)
    @server = nil
  end

  def test_phased_restart_cluster
    skip_unless :fork
    cli_server "-q -w #{workers} test/rackup/sleep.ru #{set_pumactl_args unix: true} -S #{@state_path}", unix: true

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

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
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - start, :<, (DARWIN ? 8 : 7)
    @server = nil
  end

  def test_refork_cluster
    skip_unless :fork
    wrkrs = 3
    cli_server "-q -w #{wrkrs} test/rackup/sleep.ru #{set_pumactl_args unix: true} -S #{@state_path}",
      config: 'fork_worker 50',
      unix: true

    start = Time.now

    fast_connect("sleep1", unix: true)

    # Get the PIDs of the phase 0 workers.
    phase0_worker_pids = get_worker_pids 0, wrkrs
    assert File.exist? @bind_path

    cli_pumactl "refork", unix: true

    # Get the PIDs of the phase 1 workers.
    phase1_worker_pids = get_worker_pids 1, wrkrs - 1

    msg = "phase 0 pids #{phase0_worker_pids.inspect}  phase 1 pids #{phase1_worker_pids.inspect}"

    assert_equal wrkrs    , phase0_worker_pids.length, msg
    assert_equal wrkrs - 1, phase1_worker_pids.length, msg
    assert_empty phase0_worker_pids & phase1_worker_pids, "#{msg}\nBoth workers should be replaced with new"
    assert File.exist?(@bind_path), "Bind path must exist after phased refork"

    cli_pumactl "stop", unix: true

    _, status = Process.wait2(@pid)
    assert_equal 0, status
    assert_operator Time.now - start, :<, 60
    @server = nil
  end

  def test_prune_bundler_with_multiple_workers
    skip_unless :fork

    cli_server "-q -C test/config/prune_bundler_with_multiple_workers.rb #{set_pumactl_args unix: true} -S #{@state_path}", unix: true

    socket = fast_connect(unix: true)
    headers, body = read_response(socket)

    assert_includes headers, "200 OK"
    assert_includes body, "embedded app"

    cli_pumactl "stop", unix: true

    _, _ = Process.wait2(@pid)
    @server = nil
  end

  def test_kill_unknown
    skip_if :jruby

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

  # calls pumactl with both a config file and a state file,  making sure that
  # puma files are required, see https://github.com/puma/puma/issues/3186
  def test_require_dependencies
    skip_if :jruby
    conf_path = tmp_path '.config.rb'
    @tcp_port = UniquePort.call
    @control_tcp_port = UniquePort.call

    File.write conf_path , <<~CONF
      state_path "#{@state_path}"
      bind "tcp://127.0.0.1:#{@tcp_port}"

      workers 0

      before_fork do
      end

      activate_control_app "tcp://127.0.0.1:#{@control_tcp_port}", auth_token: "#{TOKEN}"

      app do |env|
        [200, {}, ["Hello World"]]
      end
    CONF

    cli_server "-q -C #{conf_path}", no_bind: true, merge_err: true

    out = cli_pumactl_spawn "-F #{conf_path} restart", no_bind: true

    assert_includes out.read, "Command restart sent success"

    sleep 0.5 # give some time to restart
    read_response connect

    out = cli_pumactl_spawn "-S #{@state_path} status", no_bind: true
    assert_includes out.read, "Puma is started"
  end

  def control_gc_stats(unix: false)
    cli_server "-t1:1 -q test/rackup/hello.ru #{set_pumactl_args unix: unix} -S #{@state_path}"

    key = Puma::IS_MRI || TRUFFLE_HEAD ? "count" : "used"

    resp_io = cli_pumactl "gc-stats", unix: unix
    before = JSON.parse resp_io.read.split("\n", 2).last
    gc_before = before[key].to_i

    2.times { fast_connect }

    resp_io = cli_pumactl "gc", unix: unix
    # below shows gc was called (200 reply)
    assert_equal "Command gc sent success", resp_io.read.rstrip

    resp_io = cli_pumactl "gc-stats", unix: unix
    after = JSON.parse resp_io.read.split("\n", 2).last
    gc_after = after[key].to_i

    # Hitting the /gc route should increment the count by 1
    if key == "count"
      assert_operator gc_before, :<, gc_after, "make sure a gc has happened"
    elsif !Puma::IS_JRUBY
      refute_equal gc_before, gc_after, "make sure a gc has happened"
    end
  end

  def test_control_gc_stats_tcp
    @control_tcp_port = UniquePort.call
    control_gc_stats
  end

  def test_control_gc_stats_unix
    skip_unless :unix
    control_gc_stats unix: true
  end
end
