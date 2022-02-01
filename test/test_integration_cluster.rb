require_relative "helper"
require_relative "helpers/integration"

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
    skip "Intermittent failure on Ruby 2.2" if RUBY_VERSION < '2.3'
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
    cli_server "-w #{workers} test/rackup/hello.ru"
    _, status = stop_server

    assert_equal 15, status
  end

  def test_term_suppress
    cli_server "-w #{workers} -C test/config/suppress_exception.rb test/rackup/hello.ru"

    _, status = stop_server

    assert_equal 0, status
  end

  def test_term_worker_clean_exit
    skip "Intermittent failure on Ruby 2.2" if RUBY_VERSION < '2.3'

    cli_server "-w #{workers} test/rackup/hello.ru"

    # Get the PIDs of the child workers.
    worker_pids = get_worker_pids

    # Signal the workers to terminate, and wait for them to die.
    Process.kill :TERM, @pid
    Process.wait @pid

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

  # mimicking stuck workers, test restart
  def test_stuck_phased_restart
    skip_unless_signal_exist? :USR1
    worker_respawn { |phase0_worker_pids| Process.kill :USR1, @pid }
  end

  def test_worker_check_interval
    @control_tcp_port = UniquePort.call
    worker_check_interval = 1

    cli_server "-w 1 -t 1:1 --control-url tcp://#{HOST}:#{@control_tcp_port} --control-token #{TOKEN} test/rackup/hello.ru", config: "worker_check_interval #{worker_check_interval}"

    sleep worker_check_interval + 1
    last_checkin_1 = Time.parse(get_stats["worker_status"].first["last_checkin"])

    sleep worker_check_interval + 1
    last_checkin_2 = Time.parse(get_stats["worker_status"].first["last_checkin"])

    assert(last_checkin_2 > last_checkin_1)
  end

  def test_worker_boot_timeout
    timeout = 1
    worker_timeout(timeout, 2, "worker failed to boot within \\\d+ seconds", "worker_boot_timeout #{timeout}; on_worker_boot { sleep #{timeout + 1} }")
  end

  def test_worker_timeout
    skip 'Thread#name not available' unless Thread.current.respond_to?(:name)
    timeout = Puma::ConfigDefault::DefaultWorkerCheckInterval + 1
    worker_timeout(timeout, 1, "worker failed to check in within \\\d+ seconds", <<RUBY)
worker_timeout #{timeout}
on_worker_boot do
  Thread.new do
    sleep 1
    Thread.list.find {|t| t.name == 'puma stat pld'}.kill
  end
end
RUBY
  end

  def test_worker_index_is_with_in_options_limit
    skip_unless_signal_exist? :TERM

    cli_server "-C test/config/t3_conf.rb test/rackup/hello.ru"

    get_worker_pids(0, 3) # this will wait till all the processes are up

    worker_pid_was_present = File.file? "t3-worker-2-pid"

    stop_server(Integer(File.read("t3-worker-2-pid")))

    worker_index_within_number_of_workers = !File.file?("t3-worker-3-pid")

    stop_server(Integer(File.read("t3-pid")))

    File.unlink "t3-pid" if File.file? "t3-pid"
    File.unlink "t3-worker-0-pid" if File.file? "t3-worker-0-pid"
    File.unlink "t3-worker-1-pid" if File.file? "t3-worker-1-pid"
    File.unlink "t3-worker-2-pid" if File.file? "t3-worker-2-pid"
    File.unlink "t3-worker-3-pid" if File.file? "t3-worker-3-pid"

    assert(worker_pid_was_present)
    assert(worker_index_within_number_of_workers)
  end

  # use three workers to keep accepting clients
  def test_refork
    refork = Tempfile.new 'refork'
    wrkrs = 3
    cli_server "-w #{wrkrs} test/rackup/hello_with_delay.ru", config: <<RUBY
fork_worker 20
on_refork { File.write '#{refork.path}', 'Reforked' }
RUBY
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
    cli_server '', config: <<RUBY
workers 1
fork_worker 0
app do |_|
  pid = spawn('ls', [:out, :err]=>'/dev/null')
  sleep 0.01
  exitstatus = Process.detach(pid).value.exitstatus
  [200, {}, [exitstatus.to_s]]
end
RUBY
    assert_equal '0', read_body(connect)
  end

  def test_nakayoshi
    cli_server "-w #{workers} test/rackup/hello.ru", config: <<RUBY
    nakayoshi_fork true
RUBY

    output = nil
    Timeout.timeout(10) do
      until output
        output = @server.gets[/Friendly fork preparation complete/]
        sleep(0.01)
      end
    end

    assert output, "Friendly fork didn't run"
  end

  def test_prune_bundler_with_multiple_workers
    cli_server "-C test/config/prune_bundler_with_multiple_workers.rb"
    reply = read_body(connect)

    assert reply, "embedded app"
  end

  def test_load_path_includes_extra_deps
    cli_server "-w #{workers} -C test/config/prune_bundler_with_deps.rb test/rackup/hello.ru"

    load_path = []
    while (line = @server.gets) =~ /^LOAD_PATH/
      load_path << line.gsub(/^LOAD_PATH: /, '')
    end
    assert_match(%r{gems/rdoc-[\d.]+/lib$}, load_path.last)
  end

  def test_load_path_does_not_include_nio4r
    cli_server "-w #{workers} -C test/config/prune_bundler_with_deps.rb test/rackup/hello.ru"

    load_path = []
    while (line = @server.gets) =~ /^LOAD_PATH/
      load_path << line.gsub(/^LOAD_PATH: /, '')
    end

    load_path.each do |path|
      refute_match(%r{gems/nio4r-[\d.]+/lib}, path)
    end
  end

  def test_json_gem_not_required_in_master_process
    cli_server "-w #{workers} -C test/config/prune_bundler_print_json_defined.rb test/rackup/hello.ru"

    line = @server.gets
    assert_match(/defined\?\(::JSON\): nil/, line)
  end

  def test_nio4r_gem_not_required_in_master_process
    cli_server "-w #{workers} -C test/config/prune_bundler_print_nio_defined.rb test/rackup/hello.ru"

    line = @server.gets
    assert_match(/defined\?\(::NIO\): nil/, line)
  end

  def test_nio4r_gem_not_required_in_master_process_when_using_control_server
    @control_tcp_port = UniquePort.call
    control_opts = "--control-url tcp://#{HOST}:#{@control_tcp_port} --control-token #{TOKEN}"
    cli_server "-w #{workers} #{control_opts} -C test/config/prune_bundler_print_nio_defined.rb test/rackup/hello.ru"

    line = @server.gets
    assert_match(/Starting control server/, line)

    line = @server.gets
    assert_match(/defined\?\(::NIO\): nil/, line)
  end

  def test_application_is_loaded_exactly_once_if_using_preload_app
    cli_server "-w #{workers} --preload test/rackup/write_to_stdout_on_boot.ru"

    worker_load_count = 0
    worker_load_count += 1 while @server.gets =~ /^Loading app/

    assert_equal 0, worker_load_count
  end

  def test_warning_message_outputted_when_single_worker
    cli_server "-w 1 test/rackup/hello.ru"

    output = []
    while (line = @server.gets) && line !~ /Worker \d \(PID/
      output << line
    end

    assert_match(/WARNING: Detected running cluster mode with 1 worker/, output.join)
  end

  def test_warning_message_not_outputted_when_single_worker_silenced
    cli_server "-w 1 test/rackup/hello.ru", config: "silence_single_worker_warning"

    output = []
    while (line = @server.gets) && line !~ /Worker \d \(PID/
      output << line
    end

    refute_match(/WARNING: Detected running cluster mode with 1 worker/, output.join)
  end

  def test_signal_ttin
    cli_server "-w 2 test/rackup/hello.ru"
    get_worker_pids # to consume server logs

    Process.kill :TTIN, @pid

    line = @server.gets
    assert_match(/Worker 2 \(PID: \d+\) booted in/, line)
  end

  def test_signal_ttou
    cli_server "-w 2 test/rackup/hello.ru"
    get_worker_pids # to consume server logs

    Process.kill :TTOU, @pid

    line = @server.gets
    assert_match(/Worker 1 \(PID: \d+\) terminating/, line)
  end

  def test_culling_strategy_youngest
    cli_server "-w 2 test/rackup/hello.ru", config: "worker_culling_strategy :youngest"
    get_worker_pids # to consume server logs

    Process.kill :TTIN, @pid

    line = @server.gets
    assert_match(/Worker 2 \(PID: \d+\) booted in/, line)

    Process.kill :TTOU, @pid

    line = @server.gets
    assert_match(/Worker 2 \(PID: \d+\) terminating/, line)
  end

  def test_culling_strategy_oldest
    cli_server "-w 2 test/rackup/hello.ru", config: "worker_culling_strategy :oldest"
    get_worker_pids # to consume server logs

    Process.kill :TTIN, @pid

    line = @server.gets
    assert_match(/Worker 2 \(PID: \d+\) booted in/, line)

    Process.kill :TTOU, @pid

    line = @server.gets
    assert_match(/Worker 0 \(PID: \d+\) terminating/, line)
  end

  def test_culling_strategy_oldest_fork_worker
    cli_server "-w 2 test/rackup/hello.ru", config: <<RUBY
worker_culling_strategy :oldest
fork_worker
RUBY

    get_worker_pids # to consume server logs

    Process.kill :TTIN, @pid

    line = @server.gets
    assert_match(/Worker 2 \(PID: \d+\) booted in/, line)

    Process.kill :TTOU, @pid

    line = @server.gets
    assert_match(/Worker 1 \(PID: \d+\) terminating/, line)
  end

  private

  def worker_timeout(timeout, iterations, details, config)
    cli_server "-w #{workers} -t 1:1 test/rackup/hello.ru", config: config

    pids = []
    Timeout.timeout(iterations * timeout + 1) do
      (pids << @server.gets[/Terminating timed out worker \(#{details}\): (\d+)/, 1]).compact! while pids.size < workers * iterations
      pids.map!(&:to_i)
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
    qty_pids = replies.map { |body| body[/\d+\z/] }.uniq.compact.length

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

  def worker_respawn(phase = 1, size = workers)
    threads = []

    cli_server "-w #{workers} -t 1:1 -C test/config/worker_shutdown_timeout_2.rb test/rackup/sleep_pid.ru"

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
    pids.map do |pid|
      begin
        pid if Process.kill 0, pid
      rescue Errno::ESRCH
        nil
      end
    end.compact
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
