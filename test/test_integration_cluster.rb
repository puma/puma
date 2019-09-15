require_relative "helper"
require_relative "helpers/integration"

class TestIntegrationCluster < TestIntegration
  def setup
    super

    skip NO_FORK_MSG unless HAS_FORK
  end

  def test_siginfo_thread_print
    skip_unless_signal_exist? :INFO

    cli_server("-w #{WORKERS} -q test/rackup/hello.ru")
    worker_pids = get_worker_pids
    output = []
    t = Thread.new { output << @server.readlines }
    Process.kill(:INFO, worker_pids.first)
    Process.kill(:INT, @server.pid)
    t.join

    assert_match "Thread TID", output.join
  end

  def test_usr2_restart
    _, new_reply = restart_server_and_listen("-q -w #{WORKERS} test/rackup/hello.ru")
    assert_equal "Hello World", new_reply
  end

  def test_term_closes_listeners
    pid = cli_server("-w #{WORKERS} -q test/rackup/sleep.ru").pid
    threads = []
    initial_reply = nil
    next_replies = []
    condition_variable = ConditionVariable.new
    mutex = Mutex.new

    threads << Thread.new do
      s = connect "sleep1"
      mutex.synchronize { condition_variable.broadcast }
      initial_reply = read_body(s)
    end

    threads << Thread.new do
      mutex.synchronize {
        condition_variable.wait(mutex, 1)
        Process.kill("SIGTERM", pid)
      }
    end

    10.times.each do |i|
      threads << Thread.new do
        mutex.synchronize { condition_variable.wait(mutex, 1.5) }

        begin
          s = connect "sleep1"
          read_body(s)
          next_replies << :success
        rescue Errno::ECONNRESET
          # connection was accepted but then closed
          # client would see an empty response
          next_replies << :connection_reset
        rescue Errno::ECONNREFUSED
          # connection was was never accepted
          # it can therefore be re-tried before the
          # client receives an empty response
          next_replies << :connection_refused
        end
      end
    end

    threads.each(&:join)

    assert_equal "Slept 1", initial_reply

    assert_includes next_replies, :connection_refused

    refute_includes next_replies, :connection_reset
  end

  def test_term_exit_code
    pid = cli_server("-w #{WORKERS} test/rackup/hello.ru").pid
    _, status = send_term_to_server(pid)

    assert_equal 15, status
  end

  def test_term_suppress
    cli_server("-w #{WORKERS} -C test/config/suppress_exception.rb test/rackup/hello.ru")

    Process.kill(:TERM, @server.pid)
    begin
      Process.wait @server.pid
    rescue Errno::ECHILD
    end
    status = $?.exitstatus

    assert_equal 0, status
    @server.close unless @server.closed?
    @server = nil # prevent `#teardown` from killing already killed server
  end

  def test_term_worker_clean_exit
    skip "Intermittent failure on Ruby 2.2" if RUBY_VERSION < '2.3'

    pid = cli_server("-w #{WORKERS} test/rackup/hello.ru").pid

    # Get the PIDs of the child workers.
    worker_pids = get_worker_pids

    # Signal the workers to terminate, and wait for them to die.
    Process.kill :TERM, pid
    Process.wait pid

    zombies = clean_exit_pids worker_pids

    assert_empty zombies, "Process ids #{zombies} became zombies"
  end

  # mimicking stuck workers, test respawn with external SIGTERM
  def test_stuck_external_term_spawn
    worker_respawn { |l, phase0_worker_pids|
      phase0_worker_pids.each { |p| Process.kill :TERM, p }
    }
  end

  # mimicking stuck workers, test restart
  def test_stuck_phased_restart
    worker_respawn { |l, phase0_worker_pids| l.phased_restart }
  end

  private

  def worker_respawn
    skip NO_FORK_MSG unless HAS_FORK
    port = UniquePort.call
    workers_booted = 0

    conf = Puma::Configuration.new do |c|
      c.bind "tcp://#{HOST}:#{port}"
      c.threads 1, 1
      c.workers WORKERS
      c.worker_shutdown_timeout 2
      c.app TestApps::SLEEP
      c.after_worker_fork { |idx| workers_booted += 1 }
    end

    # start Puma via launcher
    thr, launcher, _e = run_launcher conf

    # make sure two workers have booted
    time = 0
    until workers_booted >= WORKERS || time >= 10
      sleep 2
      time += 2
    end

    cluster = launcher.instance_variable_get :@runner

    http0 = Net::HTTP.new HOST, port
    http1 = Net::HTTP.new HOST, port
    body0 = nil
    body1 = nil

    worker0 = Thread.new do
      begin
        req0 = Net::HTTP::Get.new "/sleep35", {}
        http0.start.request(req0) { |rep0| body0 = rep0.body }
      rescue
      end
    end

    worker1 = Thread.new do
      begin
        req1 = Net::HTTP::Get.new "/sleep40", {}
        http1.start.request(req1) { |rep1| body1 = rep1.body }
      rescue
      end
    end

    phase0_worker_pids = cluster.instance_variable_get(:@workers).map(&:pid)

    start_time = Time.now.to_f

    # below should 'cancel' the phase 0 workers, either via phased_restart or
    # externally SIGTERM'ing them
    yield launcher, phase0_worker_pids

    # make sure four workers have booted
    time = 0
    until workers_booted >= 2 * WORKERS || time >= 45
      sleep 2
      time += 2
    end

    phase1_worker_pids = cluster.instance_variable_get(:@workers).map(&:pid)

    # should be empty if all phase 0 workers cleanly exited
    phase0_exited = clean_exit_pids phase0_worker_pids

    Thread.kill worker0
    Thread.kill worker1

    launcher.stop
    assert_kind_of Thread, thr.join, "server didn't stop"

    refute_equal 'Slept 35', body0
    refute_equal 'Slept 40', body1

    # Since 35 is the shorter of the two requests, server should restart
    # and cancel both requests
    assert_operator (Time.now.to_f - start_time).round(2), :<, 35

    msg = "phase0_worker_pids #{phase0_worker_pids.inspect}  phase1_worker_pids #{phase1_worker_pids.inspect}  phase0_exited #{phase0_exited.inspect}"
    assert_equal WORKERS, phase0_worker_pids.length, msg
    assert_equal WORKERS, phase1_worker_pids.length, msg
    assert_empty phase0_worker_pids & phase1_worker_pids, "#{msg}\nBoth workers should be replaced with new"
    assert_empty phase0_exited, msg
  end

  # Returns an array of pids still in the process table, so it should
  # be empty for a clean exit.
  # Process.kill should raise the Errno::ESRCH exception, indicating the
  # process is dead and has been reaped.
  def clean_exit_pids(pids)
    pids.map do |pid|
      begin
        pid if Process.kill 0, pid
      rescue Errno::ESRCH
        nil
      end
    end.compact
  end

  def run_launcher(conf)
    wait, ready = IO.pipe
    @ios_to_close << wait << ready
    events = Puma::Events.strings
    events.on_booted { ready << "!" }

    launcher = Puma::Launcher.new conf, :events => events

    thr = Thread.new { launcher.run }

    # wait for boot from `events.on_booted`
    wait.sysread 1

    [thr, launcher, events]
  end
end
