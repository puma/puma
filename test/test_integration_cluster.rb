require_relative "helper"
require_relative "helpers/integration"

class TestIntegrationCluster < TestIntegration
  parallelize_me!

  DARWIN = !!RUBY_PLATFORM[/darwin/]

  def setup
    skip NO_FORK_MSG unless HAS_FORK
    super
  end

  def teardown
    return if skipped?
    super
  end

  def test_pre_existing_unix
    skip UNIX_SKT_MSG unless UNIX_SKT_EXIST

    File.open(@bind_path, mode: 'wb') { |f| f.puts 'pre existing' }

    cli_server "-w #{WORKERS} -q test/rackup/sleep_step.ru", unix: :unix

    stop_server

    assert File.exist?(@bind_path)

  ensure
    if UNIX_SKT_EXIST
      File.unlink @bind_path if File.exist? @bind_path
    end
  end

  def test_siginfo_thread_print
    skip_unless_signal_exist? :INFO

    cli_server "-w #{WORKERS} -q test/rackup/hello.ru"
    worker_pids = get_worker_pids
    output = []
    t = Thread.new { output << @server.readlines }
    Process.kill :INFO, worker_pids.first
    Process.kill :INT , @pid
    t.join

    assert_match "Thread TID", output.join
  end

  def test_usr2_restart
    _, new_reply = restart_server_and_listen("-q -w #{WORKERS} test/rackup/hello.ru")
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

  def test_usr1_all_respond_unix
    skip_unless_signal_exist? :USR1
    usr1_all_respond unix: true
  end

  def test_term_exit_code
    cli_server "-w #{WORKERS} test/rackup/hello.ru"
    _, status = stop_server

    assert_equal 15, status
  end

  def test_term_suppress
    cli_server "-w #{WORKERS} -C test/config/suppress_exception.rb test/rackup/hello.ru"

    _, status = stop_server

    assert_equal 0, status
  end

  def test_term_worker_clean_exit
    skip "Intermittent failure on Ruby 2.2" if RUBY_VERSION < '2.3'

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

  private

  # Send requests 10 per second.  Send 10, then :TERM server, then send another 30.
  # No more than 10 should throw Errno::ECONNRESET.
  def term_closes_listeners(unix: false)
    skip_unless_signal_exist? :TERM

    cli_server "-w #{WORKERS} -t 0:6 -q test/rackup/sleep_step.ru", unix: unix
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

    failures  = replies.count(:failure)
    successes = replies.count(:success)
    resets    = replies.count(:reset)
    refused   = replies.count(:refused)

    r_success = replies.rindex(:success)
    l_reset   = replies.index(:reset)
    r_reset   = replies.rindex(:reset)
    l_refused = replies.index(:refused)

    msg = "#{successes} successes, #{resets} resets, #{refused} refused, failures #{failures}"

    assert_equal 0, failures, msg

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
  def usr1_all_respond(unix: false)
    cli_server "-w #{WORKERS} -t 0:5 -q test/rackup/sleep_pid.ru", unix: unix
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

    responses = replies.count { |r| r[/\ASlept 1/] }
    resets    = replies.count { |r| r == :reset    }
    refused   = replies.count { |r| r == :refused  }

    # get pids from replies, generate uniq array
    qty_pids = replies.map { |body| body[/\d+\z/] }.uniq.compact.length

    msg = "#{responses} responses, #{qty_pids} uniq pids"

    assert_equal 25, responses, msg
    assert_operator qty_pids, :>, 2, msg

    msg = "#{responses} responses, #{resets} resets, #{refused} refused"

    refute_includes replies, :refused, msg

    refute_includes replies, :reset  , msg
  ensure
    unless passed?
      $debugging_info << "#{full_name}\n    #{msg}\n#{replies.inspect}\n"
    end
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

  # used with thread_run to define correct 'refused' errors
  def thread_run_refused(unix: false)
    if unix
      DARWIN ? [Errno::ENOENT, IOError] : [Errno::ENOENT]
    else
      DARWIN ? [Errno::ECONNREFUSED, Errno::EPIPE, EOFError] :
        [Errno::ECONNREFUSED]
    end
  end

  # used in loop to create several 'requests'
  def thread_run_pid(replies, delay, sleep_time, mutex, refused, unix: false)
    begin
      sleep delay
      s = connect "sleep#{sleep_time}", unix: unix
      body = read_body(s)
      mutex.synchronize { replies << body }
    rescue Errno::ECONNRESET
      # connection was accepted but then closed
      # client would see an empty response
      mutex.synchronize { replies << :reset }
    rescue *refused
      mutex.synchronize { replies << :refused }
    end
  end

  # used in loop to create several 'requests'
  def thread_run_step(replies, delay, sleep_time, step, mutex, refused, unix: false)
    begin
      sleep delay
      s = connect "sleep#{sleep_time}-#{step}", unix: unix
      body = read_body(s)
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
    end
  end


end
