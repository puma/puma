require_relative "helper"
require_relative "helpers/integration"

require "puma/configuration"

require "time"

class TestIntegrationCluster < TestIntegration
  parallelize_me! if ::Puma.mri?

  def workers ; 2 ; end

  def setup
    skip_unless :fork
    super
  end

  def teardown
    return if skipped?
    super
  end

  def test_hot_restart_does_not_drop_connections_threads
    hot_restart_does_not_drop_connections num_threads: 10, total_requests: 3_000
  end

  def test_hot_restart_does_not_drop_connections
    hot_restart_does_not_drop_connections num_threads: 1, total_requests: 1_000
  end

  def test_pre_existing_unix
    skip_unless :unix

    File.open(@bind_path, mode: 'wb') { |f| f.puts 'pre existing' }

    cli_server "-w #{workers} -q test/rackup/sleep_step.ru", unix: :unix

    stop_server

    assert File.exist?(@bind_path)

  ensure
    if UNIX_SKT_EXIST
      File.unlink @bind_path if File.exist? @bind_path
    end
  end

  def test_pre_existing_unix_stop_after_restart
    skip_unless :unix

    File.open(@bind_path, mode: 'wb') { |f| f.puts 'pre existing' }

    cli_server "-w #{workers} -q test/rackup/sleep_step.ru", unix: :unix
    connection = connect(nil, unix: true)
    restart_server connection

    connect(nil, unix: true)
    stop_server

    assert File.exist?(@bind_path)

  ensure
    if UNIX_SKT_EXIST
      File.unlink @bind_path if File.exist? @bind_path
    end
  end

  def test_siginfo_thread_print
    skip_unless_signal_exist? :INFO

    cli_server "-w #{workers} -q test/rackup/hello.ru"
    worker_pids = get_worker_pids
    output = []
    t = Thread.new { output << @server.readlines }
    Process.kill :INFO, worker_pids.first
    Process.kill :INT , @pid
    t.join

    assert_match "Thread: TID", output.join
  end

  def test_usr2_restart
    _, new_reply = restart_server_and_listen("-q -w #{workers} test/rackup/hello.ru")
    assert_equal "Hello World", new_reply
  end

  # Next two tests, one tcp, one unix
  # Send requests 10 per second.  Send 10, then :TERM server, then send another 30.
  # No more than 10 should throw Errno::ECONNRESET.

  def test_term_closes_listeners_tcp
    skip_unless_signal_exist? :TERM
    term_closes_listeners unix: false
  end

  def test_term_closes_listeners_unix
    skip_unless_signal_exist? :TERM
    term_closes_listeners unix: true
  end

  # Next two tests, one tcp, one unix
  # Send requests 1 per second.  Send 1, then :USR1 server, then send another 24.
  # All should be responded to, and at least three workers should be used

  def test_usr1_all_respond_tcp
    skip_unless_signal_exist? :USR1
    usr1_all_respond unix: false
  end

  def test_usr1_fork_worker
    skip_unless_signal_exist? :USR1
    usr1_all_respond config: '--fork-worker'
  end

  def test_usr1_all_respond_unix
    skip_unless_signal_exist? :USR1
    usr1_all_respond unix: true
  end

  def test_term_exit_code
    skip_unless_signal_exist? :TERM

    cli_server "-w #{workers} test/rackup/hello.ru"
    _, status = stop_server

    assert_equal 15, status
  end

  def test_term_suppress
    skip_unless_signal_exist? :TERM

    cli_server "-w #{workers} -C test/config/suppress_exception.rb test/rackup/hello.ru"

    _, status = stop_server

    assert_equal 0, status
  end

  def test_on_booted_and_on_stopped
    skip_unless_signal_exist? :TERM
    cli_server "-w #{workers} -C test/config/event_on_booted_and_on_stopped.rb -C test/config/event_on_booted_exit.rb test/rackup/hello.ru"

    # above checks 'Ctrl-C', below is logged after workers boot
    assert wait_for_server_to_include('on_booted called')
    assert wait_for_server_to_include('Goodbye!')
    # below logged after workers are stopped
    assert wait_for_server_to_include('on_stopped called')
  end

  def test_term_worker_clean_exit
    skip_unless_signal_exist? :TERM
    cli_server "-w #{workers} test/rackup/hello.ru"

    # Get the PIDs of the child workers.
    worker_pids = get_worker_pids

    # Signal the workers to terminate, and wait for them to die.
    Process.kill :TERM, @pid
    wait_server 15

    zombies = bad_exit_pids worker_pids

    assert_empty zombies, "Process ids #{zombies} became zombies"
  end

  # mimicking stuck workers, test respawn with external TERM
  def test_stuck_external_term_spawn
    skip_unless_signal_exist? :TERM

    worker_respawn(0) do |phase0_worker_pids|
      last = phase0_worker_pids.last
      # test is tricky if only one worker is TERM'd, so kill all but
      # spread out, so all aren't killed at once
      phase0_worker_pids.each do |pid|
        Process.kill :TERM, pid
        sleep 4 unless pid == last
      end
    end
  end

  # From Ruby 2.6 to 3.2, `Process.detach` can delay or prevent
  # `Process.wait2(-1)` from detecting a terminated child:
  # https://bugs.ruby-lang.org/issues/19837. However,
  # `Process.wait2(<child pid>)` still works properly. This bug has
  # been fixed in Ruby 3.3.
  def test_workers_respawn_with_process_detach
    skip_unless_signal_exist? :KILL

    config = 'test/config/process_detach_before_fork.rb'

    worker_respawn(0, workers, config) do |phase0_worker_pids|
      phase0_worker_pids.each do |pid|
        Process.kill :KILL, pid
      end
    end

    # `test/config/process_detach_before_fork.rb` forks and detaches a
    # process.  Since MiniTest attempts to join all threads before
    # finishing, terminate the process so that the test can end quickly
    # if it passes.
    pid_filename = File.join(Dir.tmpdir, 'process_detach_test.pid')
    if File.exist?(pid_filename)
      pid = File.read(pid_filename).chomp.to_i
      File.unlink(pid_filename)
      Process.kill :TERM, pid if pid > 0
    end
  end

  # mimicking stuck workers, test restart
  def test_stuck_phased_restart
    skip_unless_signal_exist? :USR1
    worker_respawn { |phase0_worker_pids| Process.kill :USR1, @pid }
  end

  def test_worker_check_interval
    # iso8601 2022-12-14T00:05:49Z
    re_8601 = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/
    @control_tcp_port = UniquePort.call
    worker_check_interval = 1

    cli_server "-w 1 -t 1:1 --control-url tcp://#{HOST}:#{@control_tcp_port} --control-token #{TOKEN} test/rackup/hello.ru", config: "worker_check_interval #{worker_check_interval}"

    sleep worker_check_interval + 1
    checkin_1 = get_stats["worker_status"].first["last_checkin"]
    assert_match re_8601, checkin_1

    sleep worker_check_interval + 1
    checkin_2 = get_stats["worker_status"].first["last_checkin"]
    assert_match re_8601, checkin_2

    # iso8601 sorts as a string
    assert_operator(checkin_2, :>, checkin_1)
  end

  def test_worker_boot_timeout
    timeout = 1
    worker_timeout(timeout, 2, "failed to boot within \\\d+ seconds", "worker_boot_timeout #{timeout}; on_worker_boot { sleep #{timeout + 1} }")
  end

  def test_worker_timeout
    skip 'Thread#name not available' unless Thread.current.respond_to?(:name)
    timeout = Puma::Configuration::DEFAULTS[:worker_check_interval] + 1
    config = <<~CONFIG
      worker_timeout #{timeout}
      on_worker_boot do
        Thread.new do
          sleep 1
          Thread.list.find {|t| t.name == 'puma stat pld'}.kill
        end
      end
    CONFIG

    worker_timeout(timeout, 1, "failed to check in within \\\d+ seconds", config)
  end

  def test_idle_timeout
    cli_server "-w #{workers} test/rackup/hello.ru", config: "idle_timeout 1"

    get_worker_pids # wait for workers to boot

    10.times {
      fast_connect
      sleep 0.5
    }

    sleep 1.15

    assert_raises Errno::ECONNREFUSED, "Connection refused" do
      connect
    end
  end

  def test_worker_index_is_with_in_options_limit
    skip_unless_signal_exist? :TERM

    cli_server "-C test/config/t3_conf.rb test/rackup/hello.ru"

    get_worker_pids(0, 3) # this will wait till all the processes are up

    worker_pid_was_present = File.file? "t3-worker-2-pid"

    stop_server(Integer(File.read("t3-worker-2-pid")))

    worker_index_within_number_of_workers = !File.file?("t3-worker-3-pid")

    stop_server(Integer(File.read("t3-pid")))

    assert(worker_pid_was_present)
    assert(worker_index_within_number_of_workers)
  ensure
    File.unlink "t3-pid" if File.file? "t3-pid"
    File.unlink "t3-worker-0-pid" if File.file? "t3-worker-0-pid"
    File.unlink "t3-worker-1-pid" if File.file? "t3-worker-1-pid"
    File.unlink "t3-worker-2-pid" if File.file? "t3-worker-2-pid"
    File.unlink "t3-worker-3-pid" if File.file? "t3-worker-3-pid"
  end

  # use three workers to keep accepting clients
  def test_fork_worker_on_refork
    refork = Tempfile.new 'refork'
    wrkrs = 3
    cli_server "-w #{wrkrs} test/rackup/hello_with_delay.ru", config: <<~CONFIG
      fork_worker 20
      on_refork { File.write '#{refork.path}', 'Reforked' }
    CONFIG

    pids = get_worker_pids 0, wrkrs

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

    refute_includes pids, get_worker_pids(1, wrkrs - 1)
  end

  def test_fork_worker_spawn
    cli_server '', config: <<~CONFIG
      workers 1
      fork_worker 0
      app do |_|
        pid = spawn('ls', [:out, :err]=>'/dev/null')
        sleep 0.01
        exitstatus = Process.detach(pid).value.exitstatus
        [200, {}, [exitstatus.to_s]]
      end
    CONFIG
    assert_equal '0', read_body(connect)
  end

  def test_fork_worker_phased_restart_with_high_worker_count
    worker_count = 10

    cli_server "test/rackup/hello.ru", config: <<~CONFIG
      fork_worker 0
      worker_check_interval 1
      # lower worker timeout from default (60) to avoid test timeout
      worker_timeout 2
      # to simulate worker 0 timeout, total boot time for all workers
      # needs to exceed single worker timeout
      workers #{worker_count}
    CONFIG

    # workers is the default
    get_worker_pids 0, worker_count

    Process.kill :USR1, @pid

    get_worker_pids 1, worker_count

    # below is so all of @server_log isn't output for failure
    refute @server_log[/.*Terminating timed out worker.*/]
  end

  def test_prune_bundler_with_multiple_workers
    cli_server "-C test/config/prune_bundler_with_multiple_workers.rb"
    reply = read_body(connect)

    assert reply, "embedded app"
  end

  def test_load_path_includes_extra_deps
    cli_server "-w #{workers} -C test/config/prune_bundler_with_deps.rb test/rackup/hello.ru"

    assert wait_for_server_to_match(/^LOAD_PATH: .+?\/gems\/minitest-[\d.]+\/lib$/)
  end

  def test_load_path_does_not_include_nio4r
    cli_server "-w #{workers} -C test/config/prune_bundler_with_deps.rb test/rackup/hello.ru"

    get_worker_pids # reads thru 'LOAD_PATH:' data

    # make sure we're seeing LOAD_PATH: logging
    assert_match(/^LOAD_PATH: .+\/gems\/minitest-[\d.]+\/lib$/, @server_log)
    refute_match(%r{gems/nio4r-[\d.]+/lib$}, @server_log)
  end

  def test_json_gem_not_required_in_master_process
    cli_server "-w #{workers} -C test/config/prune_bundler_print_json_defined.rb test/rackup/hello.ru"

    assert wait_for_server_to_include('defined?(::JSON): nil')
  end

  def test_nio4r_gem_not_required_in_master_process
    cli_server "-w #{workers} -C test/config/prune_bundler_print_nio_defined.rb test/rackup/hello.ru"

    assert wait_for_server_to_include('defined?(::NIO): nil')
  end

  def test_nio4r_gem_not_required_in_master_process_when_using_control_server
    @control_tcp_port = UniquePort.call
    control_opts = "--control-url tcp://#{HOST}:#{@control_tcp_port} --control-token #{TOKEN}"
    cli_server "-w #{workers} #{control_opts} -C test/config/prune_bundler_print_nio_defined.rb test/rackup/hello.ru"

    assert wait_for_server_to_include('Starting control server')

    assert wait_for_server_to_include('defined?(::NIO): nil')
  end

  def test_application_is_loaded_exactly_once_if_using_preload_app
    cli_server "-w #{workers} --preload test/rackup/write_to_stdout_on_boot.ru"

    get_worker_pids
    loading_app_count = @server_log.scan('Loading app').length
    assert_equal 1, loading_app_count
  end

  def test_warning_message_outputted_when_single_worker
    cli_server "-w 1 test/rackup/hello.ru"

    assert wait_for_server_to_include('Worker 0 (PID')
    assert_match(/WARNING: Detected running cluster mode with 1 worker/, @server_log)
  end

  def test_warning_message_not_outputted_when_single_worker_silenced
    cli_server "-w 1 test/rackup/hello.ru", config: "silence_single_worker_warning"

    assert wait_for_server_to_include('Worker 0 (PID')
    refute_match(/WARNING: Detected running cluster mode with 1 worker/, @server_log)
  end

  def test_signal_ttin
    cli_server "-w 2 test/rackup/hello.ru"
    get_worker_pids # to consume server logs

    Process.kill :TTIN, @pid

    assert wait_for_server_to_match(/Worker 2 \(PID: \d+\) booted in/)
  end

  def test_signal_ttou
    cli_server "-w 2 test/rackup/hello.ru"
    get_worker_pids # to consume server logs

    Process.kill :TTOU, @pid

    assert wait_for_server_to_match(/Worker 1 \(PID: \d+\) terminating/)
  end

  def test_culling_strategy_youngest
    cli_server "-w 2 test/rackup/hello.ru", config: "worker_culling_strategy :youngest"
    get_worker_pids # to consume server logs

    Process.kill :TTIN, @pid

    assert wait_for_server_to_match(/Worker 2 \(PID: \d+\) booted in/)

    Process.kill :TTOU, @pid

    assert wait_for_server_to_match(/Worker 2 \(PID: \d+\) terminating/)
  end

  def test_culling_strategy_oldest
    cli_server "-w 2 test/rackup/hello.ru", config: "worker_culling_strategy :oldest"
    get_worker_pids # to consume server logs

    Process.kill :TTIN, @pid

    assert wait_for_server_to_match(/Worker 2 \(PID: \d+\) booted in/)

    Process.kill :TTOU, @pid

    assert wait_for_server_to_match(/Worker 0 \(PID: \d+\) terminating/)
  end

  def test_culling_strategy_oldest_fork_worker
    cli_server "-w 2 test/rackup/hello.ru", puma_debug: true, config: <<~CONFIG
      worker_culling_strategy :oldest
      fork_worker
    CONFIG

    get_worker_pids # to consume server logs
    assert wait_for_server_to_match(/Server started - worker 0/) # ensure server is started for worker-0

    Process.kill :TTIN, @pid

    assert wait_for_server_to_match(/Worker 2 \(PID: \d+\) booted in/)

    Process.kill :TTOU, @pid

    assert wait_for_server_to_match(/Worker 1 \(PID: \d+\) terminating/)
  end

  def test_hook_data
    skip_unless_signal_exist? :TERM

    cli_server "-C test/config/hook_data.rb test/rackup/hello.ru"
    get_worker_pids 0, 2 # make sure workers are booted
    stop_server

    ary = Array.new(2) do |_index|
      wait_for_server_to_match(/(index \d data \d)/, 1)
    end.sort

    assert 'index 0 data 0', ary[0]
    assert 'index 1 data 1', ary[1]
  end

  def test_worker_hook_warning_cli
    cli_server "-w2 test/rackup/hello.ru", config: <<~CONFIG
      on_worker_boot(:test) do |index, data|
        data[:test] = index
      end
    CONFIG

    get_worker_pids
    line = @server_log[/.+on_worker_boot.+/]
    refute line, "Warning below should not be shown!\n#{line}"
  end

  def test_worker_hook_warning_web_concurrency
    cli_server "test/rackup/hello.ru",
      env: { 'WEB_CONCURRENCY' => '2'},
      config: <<~CONFIG
        on_worker_boot(:test) do |index, data|
          data[:test] = index
        end
      CONFIG

    get_worker_pids
    line = @server_log[/.+on_worker_boot.+/]
    refute line, "Warning below should not be shown!\n#{line}"
  end

  def test_puma_debug_loaded_exts
    cli_server "-w #{workers} test/rackup/hello.ru", puma_debug: true

    assert wait_for_server_to_include('Loaded Extensions - worker 0:')
    assert wait_for_server_to_include('Loaded Extensions - master:')
    @pid = @server.pid
  end

  private

  def worker_timeout(timeout, iterations, details, config, log: nil)
    cli_server "-w #{workers} -t 1:1 test/rackup/hello.ru", config: config

    pids = []
    re = /Terminating timed out worker \(Worker \d+ #{details}\): (\d+)/

    Timeout.timeout(iterations * (timeout + 1)) do
      while (pids.size < workers * iterations)
        idx = wait_for_server_to_match(re, 1).to_i
        pids << idx
      end
    end

    assert_equal pids, pids.uniq
  end

  # Send requests 10 per second.  Send 10, then :TERM server, then send another 30.
  # No more than 10 should throw Errno::ECONNRESET.
  def term_closes_listeners(unix: false)
    skip_unless_signal_exist? :TERM

    cli_server "-w #{workers} -t 0:6 -q test/rackup/sleep_step.ru", unix: unix
    threads = []
    replies = []
    mutex = Mutex.new
    div   = 10

    refused = thread_run_refused unix: unix

    41.times.each do |i|
      if i == 10
        threads << Thread.new do
          sleep i.to_f/div
          Process.kill :TERM, @pid
          mutex.synchronize { replies[i] = :term_sent }
        end
      else
        threads << Thread.new do
          thread_run_step replies, i.to_f/div, 1, i, mutex, refused, unix: unix
        end
      end
    end

    threads.each(&:join)

    failures      = replies.count(:failure)
    successes     = replies.count(:success)
    resets        = replies.count(:reset)
    refused       = replies.count(:refused)
    read_timeouts = replies.count(:read_timeout)

    r_success = replies.rindex(:success)
    l_reset   = replies.index(:reset)
    r_reset   = replies.rindex(:reset)
    l_refused = replies.index(:refused)

    msg = "#{successes} successes, #{resets} resets, #{refused} refused, #{failures} failures, #{read_timeouts} read timeouts"

    assert_equal 0, failures, msg
    assert_equal 0, read_timeouts, msg

    assert_operator 9,  :<=, successes, msg

    assert_operator 10, :>=, resets   , msg

    assert_operator 20, :<=, refused  , msg

    # Interleaved asserts
    # UNIX binders do not generate :reset items
    if l_reset
      assert_operator r_success, :<, l_reset  , "Interleaved success and reset"
      assert_operator r_reset  , :<, l_refused, "Interleaved reset and refused"
    else
      assert_operator r_success, :<, l_refused, "Interleaved success and refused"
    end

  ensure
    if passed?
      $debugging_info << "#{full_name}\n    #{msg}\n"
    else
      $debugging_info << "#{full_name}\n    #{msg}\n#{replies.inspect}\n"
    end
  end

  # Send requests 1 per second.  Send 1, then :USR1 server, then send another 24.
  # All should be responded to, and at least three workers should be used
  def usr1_all_respond(unix: false, config: '')
    cli_server "-w #{workers} -t 0:5 -q test/rackup/sleep_pid.ru #{config}", unix: unix
    threads = []
    replies = []
    mutex = Mutex.new

    s = connect "sleep1", unix: unix
    replies << read_body(s)

    Process.kill :USR1, @pid

    refused = thread_run_refused unix: unix

    24.times do |delay|
      threads << Thread.new do
        thread_run_pid replies, delay, 1, mutex, refused, unix: unix
      end
    end

    threads.each(&:join)

    responses     = replies.count { |r| r[/\ASlept 1/] }
    resets        = replies.count { |r| r == :reset    }
    refused       = replies.count { |r| r == :refused  }
    read_timeouts = replies.count { |r| r == :read_timeout }

    # get pids from replies, generate uniq array
    t = replies.map { |body| body[/\d+\z/] }
    t.uniq!; t.compact!
    qty_pids = t.length

    msg = "#{responses} responses, #{qty_pids} uniq pids"

    assert_equal 25, responses, msg
    assert_operator qty_pids, :>, 2, msg

    msg = "#{responses} responses, #{resets} resets, #{refused} refused, #{read_timeouts} read timeouts"

    assert_equal 0, refused, msg

    assert_equal 0, resets, msg

    assert_equal 0, read_timeouts, msg
  ensure
    unless passed?
      $debugging_info << "#{full_name}\n    #{msg}\n#{replies.inspect}\n"
    end
  end

  def worker_respawn(phase = 1, size = workers, config = 'test/config/worker_shutdown_timeout_2.rb')
    threads = []

    cli_server "-w #{workers} -t 1:1 -C #{config} test/rackup/sleep_pid.ru"

    # make sure two workers have booted
    phase0_worker_pids = get_worker_pids

    [35, 40].each do |sleep_time|
      threads << Thread.new do
        begin
          connect "sleep#{sleep_time}"
          # stuck connections will raise IOError or Errno::ECONNRESET
          # when shutdown
        rescue IOError, Errno::ECONNRESET
        end
      end
    end

    @start_time = Time.now.to_f

    # below should 'cancel' the phase 0 workers, either via phased_restart or
    # externally TERM'ing them
    yield phase0_worker_pids

    # wait for new workers to boot
    phase1_worker_pids = get_worker_pids phase

    # should be empty if all phase 0 workers cleanly exited
    phase0_exited = bad_exit_pids phase0_worker_pids

    # Since 35 is the shorter of the two requests, server should restart
    # and cancel both requests
    assert_operator (Time.now.to_f - @start_time).round(2), :<, 35

    msg = "phase0_worker_pids #{phase0_worker_pids.inspect}  phase1_worker_pids #{phase1_worker_pids.inspect}  phase0_exited #{phase0_exited.inspect}"
    assert_equal workers, phase0_worker_pids.length, msg

    assert_equal workers, phase1_worker_pids.length, msg
    assert_empty phase0_worker_pids & phase1_worker_pids, "#{msg}\nBoth workers should be replaced with new"

    assert_empty phase0_exited, msg

    threads.each { |th| Thread.kill th }
  end

  # Returns an array of pids still in the process table, so it should
  # be empty for a clean exit.
  # Process.kill should raise the Errno::ESRCH exception, indicating the
  # process is dead and has been reaped.
  def bad_exit_pids(pids)
    t = pids.map do |pid|
      begin
        pid if Process.kill 0, pid
      rescue Errno::ESRCH
        nil
      end
    end
    t.compact!; t
  end

  # used in loop to create several 'requests'
  def thread_run_pid(replies, delay, sleep_time, mutex, refused, unix: false)
    begin
      sleep delay
      s = fast_connect "sleep#{sleep_time}", unix: unix
      body = read_body(s, 20)
      mutex.synchronize { replies << body }
    rescue Errno::ECONNRESET
      # connection was accepted but then closed
      # client would see an empty response
      mutex.synchronize { replies << :reset }
    rescue *refused
      mutex.synchronize { replies << :refused }
    rescue Timeout::Error
      mutex.synchronize { replies << :read_timeout }
    end
  end

  # used in loop to create several 'requests'
  def thread_run_step(replies, delay, sleep_time, step, mutex, refused, unix: false)
    begin
      sleep delay
      s = connect "sleep#{sleep_time}-#{step}", unix: unix
      body = read_body(s, 20)
      if body[/\ASlept /]
        mutex.synchronize { replies[step] = :success }
      else
        mutex.synchronize { replies[step] = :failure }
      end
    rescue Errno::ECONNRESET
      # connection was accepted but then closed
      # client would see an empty response
      mutex.synchronize { replies[step] = :reset }
    rescue *refused
      mutex.synchronize { replies[step] = :refused }
    rescue Timeout::Error
      mutex.synchronize { replies[step] = :read_timeout }
    end
  end
end if ::Process.respond_to?(:fork)
