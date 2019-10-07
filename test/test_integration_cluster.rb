require_relative "helper"
require_relative "helpers/integration"

class TestIntegrationCluster < TestIntegration
  parallelize_me! unless Puma.jruby?

  def teardown
    return if skipped?
    super
  end

  def test_pre_existing_unix
    skip UNIX_SKT_MSG unless HAS_UNIX
    setup_puma bind: :unix, ctrl: :unix

    File.open(@path_bind, mode: 'wb') { |f| f.puts 'pre existing' }

    cli_server "-w #{WORKERS} -q test/rackup/sleep_step.ru"

    stop_server_wait

    assert File.exist?(@path_bind)

  ensure
    if HAS_UNIX
      File.unlink(@path_bind) if File.exist? @path_bind
    end
  end

  def test_thread_status_sgnl
    skip_unless_signal_exist? :INFO
    setup_puma bind: :tcp, ctrl: :tcp

    cli_server "-w #{WORKERS} -q test/rackup/hello.ru"
    worker_pids = get_worker_pids

    Process.kill :INFO, worker_pids.first
    assert_io 'Thread: TID'
  end

  def test_thread_status_sock
    setup_puma bind: :tcp, ctrl: :tcp

    cli_server "-w #{WORKERS} -q test/rackup/hello.ru"

    out, _ = run_pumactl 'thread-status'
    assert_match 'Thread: TID', out
  end

  # Next three tests, two signal, one with tcp bind, the other with unix.  Third
  # is tcp bind and tcp control.
  # Send requests 10 per second.  Send 10, then :TERM server, then send another 30.
  # No more than 10 should throw Errno::ECONNRESET.

  def test_stop_closes_listeners_tcp_sgnl
    skip_unless_signal_exist? :TERM
    setup_puma bind: :tcp, ctrl: :pid
    stop_closes_listeners "-w #{WORKERS}"
  end

  def test_stop_closes_listeners_unix_sgnl
    skip_unless_signal_exist? :TERM
    setup_puma bind: :unix, ctrl: :pid
    stop_closes_listeners "-w #{WORKERS}"
  end

  def test_stop_closes_listeners_tcp_sock
    setup_puma bind: :tcp, ctrl: :tcp
    stop_closes_listeners "-w #{WORKERS}"
  end

  # Next two tests, one tcp, one unix
  # Send requests 1 per second.  Send 1, then :USR1 server, then send another 34.
  # All should be responded to, and at least three workers should be used

  def test_phased_restart_all_respond_tcp_sgnl
    skip_unless_signal_exist? :USR1
    setup_puma bind: :tcp, ctrl: :pid
    phased_restart_all_respond
  end

  def test_phased_restart_all_respond_unix_sgnl
    skip_unless_signal_exist? :USR1
    setup_puma bind: :unix, ctrl: :pid
    phased_restart_all_respond
  end

  def test_phased_restart_all_respond_tcp_sock
    setup_puma bind: :tcp, ctrl: :tcp
    phased_restart_all_respond
  end

  def test_term_exit_code
    setup_puma bind: :tcp, ctrl: :pid
    cli_server "-w #{WORKERS} test/rackup/hello.ru"
    run_pumactl 'stop'

    begin
      _, status = Process.wait2 @pid
      assert_equal 15, status
    rescue Errno::ECHILD
    end
  end

  def test_term_suppress
    setup_puma bind: :tcp, ctrl: :pid
    cli_server "-w #{WORKERS} -C test/config/suppress_exception.rb test/rackup/hello.ru"
    run_pumactl 'stop'

    begin
      _, status = Process.wait2 @pid
      assert_equal 0, status
    rescue Errno::ECHILD
    end
  end

  def test_term_worker_clean_exit
    skip "Intermittent failure on Ruby 2.2" if RUBY_VERSION < '2.3'

    setup_puma bind: :tcp, ctrl: :pid
    cli_server "-w #{WORKERS} test/rackup/hello.ru"

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

    setup_puma bind: :tcp, ctrl: :pid
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

    setup_puma bind: :tcp, ctrl: :pid
    worker_respawn { |phase0_worker_pids| Process.kill :USR1, @pid }
  end

  private

  # Send requests 1 per second.  Send 1, then :USR1 server, then send another 34.
  # All should be responded to, and at least three workers should be used
  def phased_restart_all_respond
    cli_server "-w #{WORKERS} -t 0:5 -q test/rackup/sleep_pid.ru"
    threads = []
    replies = []
    mutex = Mutex.new

    replies << read_body('sleep1')

    run_pumactl 'phased-restart'

    refused = thread_run_refused

    34.times do |delay|
      threads << Thread.new do
        thread_run_pid replies, delay, 1, mutex, refused
      end
    end

    threads.each(&:join)

    responses = replies.count { |r| r[/\ASlept 1/] }
    resets    = replies.count { |r| r == :reset    }
    refused   = replies.count { |r| r == :refused  }

    # get pids from replies, generate uniq array
    qty_pids = replies.map { |body| body[/\d+\z/] }.uniq.compact.length

    msg = "#{responses} responses, #{qty_pids} uniq pids"

    assert_equal 35, responses, msg
    assert_operator qty_pids, :>, 2, msg

    msg = "#{responses} responses, #{resets} resets, #{refused} refused"

    refute_includes replies, :refused, msg

    refute_includes replies, :reset  , msg
  end

  def worker_respawn(phase = 1, size = WORKERS)
    threads = []

    cli_server "-w #{WORKERS} -t 1:1 -C test/config/worker_shutdown_timeout_2.rb test/rackup/sleep_pid.ru"

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
    assert_equal WORKERS, phase0_worker_pids.length, msg

    assert_equal WORKERS, phase1_worker_pids.length, msg
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
  def thread_run_pid(replies, delay, sleep_time, mutex, refused)
    begin
      sleep delay
      body = read_body(connect "sleep#{sleep_time}")
      mutex.synchronize { replies << body }
    rescue Errno::ECONNRESET
      # connection was accepted but then closed
      # client would see an empty response
      mutex.synchronize { replies << :reset }
    rescue *refused
      mutex.synchronize { replies << :refused }
    end
  end
end if ::Puma::HAS_FORK

# restart sets ENV variables, so these can't run parallel
# note: not phased-restart
class TestIntegrationClusterSerial < TestIntegration

  def teardown
    return if skipped?
    super
  end

  def test_restart_sgnl
    skip_unless_signal_exist? :USR2
    setup_puma bind: :tcp, ctrl: :pid
    pre, post = restart_server_and_listen "-q -w #{WORKERS} test/rackup/hello.ru"
    assert_equal "Hello World", pre
    assert_equal "Hello World", post
  end

  def test_restart_sock
    setup_puma bind: :tcp, ctrl: :tcp
    pre, post = restart_server_and_listen "-q -w #{WORKERS} test/rackup/hello.ru"
    assert_equal "Hello World", pre
    assert_equal "Hello World", post
  end
end if ::Puma::HAS_FORK
