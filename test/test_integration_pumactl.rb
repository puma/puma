# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/test_puma/server_spawn"

class TestIntegrationPumactl < TestPuma::ServerSpawn
  parallelize_me! if ::Puma::IS_MRI

  def workers ; 2 ; end

  def teardown
    refute control_path && File.exist?(control_path), "Control path must be removed after stop"
  end

  def test_stop_tcp
    ctrl_stop_halt 'stop', :tcp
  end

  def test_stop_unix
    ctrl_stop_halt 'stop', :unix
  end

  def test_halt_unix
    ctrl_stop_halt 'halt', :unix
  end

  def ctrl_stop_halt(command, type)
    set_control_type type

    server_spawn "-q -S #{state_path} test/rackup/sleep.ru"

    out = cli_pumactl command

    assert wait_for_server_to_include('Goodbye')

    assert_equal "Command #{command} sent success", out.read.strip

    assert_empty @server_err.read.strip

  ensure
    @server = nil if ::Puma::IS_WINDOWS # see ServerSpawn#after_teardown
  end

  def test_phased_restart_cluster
    skip_unless :fork
    set_bind_type :unix
    set_control_type :unix
    server_spawn "-q -w #{workers} -S #{state_path} test/rackup/sleep.ru"

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    send_http "GET /sleep1 HTTP/1.0\r\n\r\n"

    # Get the PIDs of the phase 0 workers.
    phase0_worker_pids = get_worker_pids 0
    assert File.exist? bind_path

    # Phased restart
    cli_pumactl "phased-restart"

    # Get the PIDs of the phase 1 workers.
    phase1_worker_pids = get_worker_pids 1

    msg = "phase 0 pids #{phase0_worker_pids.inspect}  phase 1 pids #{phase1_worker_pids.inspect}"

    assert_equal workers, phase0_worker_pids.length, msg
    assert_equal workers, phase1_worker_pids.length, msg
    assert_empty phase0_worker_pids & phase1_worker_pids, "#{msg}\nBoth workers should be replaced with new"
    assert File.exist?(bind_path), "Bind path must exist after phased restart"

    cli_pumactl "stop"

    _, status = Process.wait2 @spawn_pid
    assert_equal 0, status
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - start, :<, (DARWIN ? 8 : 7)

  ensure
    @server = nil if ::Puma::IS_WINDOWS # see ServerSpawn#after_teardown
  end

  def test_refork_cluster
    skip_unless :fork
    set_bind_type :unix
    set_control_type :unix
    wrkrs = 3
    server_spawn "-q -w#{wrkrs} -t1:5 -S #{state_path} test/rackup/sleep.ru",
      config: 'fork_worker 50'

    3.times { send_http "GET /sleep1 HTTP/1.0\r\n\r\n" }

    # Get the PIDs of the phase 0 workers.
    phase0_worker_pids = get_worker_pids 0, wrkrs

    start = Time.now

    assert File.exist? bind_path

    cli_pumactl "refork"

    # Get the PIDs of the phase 1 workers.
    phase1_worker_pids = get_worker_pids 1, wrkrs - 1

    msg = "phase 0 pids #{phase0_worker_pids.inspect}  phase 1 pids #{phase1_worker_pids.inspect}"

    assert_equal wrkrs    , phase0_worker_pids.length, msg
    assert_equal wrkrs - 1, phase1_worker_pids.length, msg
    assert_empty phase0_worker_pids & phase1_worker_pids, "#{msg}\nBoth workers should be replaced with new"
    assert File.exist?(bind_path), "Bind path must exist after phased refork"

    cli_pumactl "stop"

    _, status = Process.wait2 @spawn_pid
    assert_equal 0, status
    assert_operator Time.now - start, :<, (DARWIN ? 8 : 6)
  ensure
    @pid = nil
    @spawn_pid = nil
    @server = nil if ::Puma::IS_WINDOWS # see ServerSpawn#after_teardown
  end

  def test_prune_bundler_with_multiple_workers
    skip_unless :fork
    set_bind_type :unix
    set_control_type :unix

    server_spawn "-q -S #{state_path}", config: <<~CONFIG
      require 'bundler/setup'
      Bundler.setup

      prune_bundler true

      workers 2

      app do |env|
        [200, {}, ["embedded app"]]
      end

      lowlevel_error_handler do |err|
        [200, {}, ["error page"]]
      end
    CONFIG

    response = send_http_read_response

    assert_includes response.status, "200 OK"
    assert_includes response.body, "embedded app"

    cli_pumactl "stop"

    _, _ = Process.wait2 @spawn_pid

  ensure
    @pid = nil
    @spawn_pid = nil
    @server = nil if ::Puma::IS_WINDOWS # see ServerSpawn#after_teardown
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
  #
  # uses cli_pumactl_spawn so running it is isolated from what is loaded in the
  # test process
  def test_require_dependencies
    skip_if :jruby # take to long to spawn three processes
    set_control_type :tcp

    server_spawn "-q", no_bind: true, config: <<~CONFIG
      state_path '#{state_path}'

      app do |env|
        [200, {}, ['Hello World']]
      end
    CONFIG

    out = cli_pumactl_spawn "-F #{config_path} restart", no_bind: true

    assert_includes out.read, "Command restart sent success"

    assert wait_for_server_to_include('Ctrl-C')

    send_http

    out = cli_pumactl_spawn "-S #{state_path} status", no_bind: true
    assert_includes out.read, "Puma is started"

    out = cli_pumactl_spawn "-S #{state_path} stop", no_bind: true
    assert_includes out.read, "Command stop sent success"
  end

  def control_gc_stats(type)
    set_control_type type
    server_spawn "-t1:1 -q -S #{state_path} test/rackup/hello.ru"

    key = Puma::IS_MRI || TRUFFLE_HEAD ? "count" : "used"

    resp_io = cli_pumactl "gc-stats"
    before = JSON.parse resp_io.read.split("\n", 2).last
    gc_before = before[key].to_i

    2.times { send_http_read_response }

    resp_io = cli_pumactl "gc"
    # below shows gc was called (200 reply)
    assert_equal "Command gc sent success", resp_io.read.rstrip

    2.times { send_http_read_response } # helpful for JRuby ?

    resp_io = cli_pumactl "gc-stats"
    after = JSON.parse resp_io.read.split("\n", 2).last
    gc_after = after[key].to_i

    # Hitting the /gc route should increment the count by 1
    if key == "count"
      assert_operator gc_before, :<, gc_after, "make sure a gc has happened"
    elsif !(Puma::IS_OSX && Puma::IS_JRUBY)
      refute_equal gc_before, gc_after, "make sure a gc has happened"
    end
  end

  def test_control_gc_stats_tcp
    control_gc_stats :tcp
  end

  def test_control_gc_stats_unix
    control_gc_stats :unix
    # below needed to remove unix control socket
    cli_pumactl 'stop'
    wait_for_server_to_include 'Goodbye'
    sleep 1.0 if ::Puma::IS_JRUBY # small delay for control UNIXSocket removal
  end
end
