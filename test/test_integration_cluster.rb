# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/test_puma/server_spawn"

require "puma/configuration"

require "time"

class TestIntegrationCluster < TestPuma::ServerSpawn
  parallelize_me! if ::Puma::IS_MRI

  def setup
    set_workers 2
  end

  def test_hot_restart_does_not_drop_connections_threads
    hot_restart_does_not_drop_connections num_threads: 10, total_requests: 3_000
  end

  def test_hot_restart_does_not_drop_connections
    hot_restart_does_not_drop_connections num_threads: 1, total_requests: 1_000
  end

  def test_pre_existing_unix
    set_bind_type :unix

    File.write(bind_path, 'pre existing', mode: 'wb')

    server_spawn "-w#{workers} -q test/rackup/sleep_step.ru"

    stop_server

    assert File.exist?(bind_path)
    File.unlink bind_path
  end

  def test_pre_existing_unix_stop_after_restart
    set_bind_type :unix

    File.write(bind_path, 'pre existing', mode: 'wb')

    server_spawn "-w#{workers} -q test/rackup/sleep_step.ru"
    socket = send_http
    restart_server socket

    send_http
    stop_server

    assert File.exist?(bind_path)
    File.unlink bind_path
  end

  def test_siginfo_thread_print
    skip_unless_signal_exist? :INFO

    server_spawn "-w#{workers} -q test/rackup/hello.ru"
    worker_pids = get_worker_pids
    output = []
    t = Thread.new { output << @server.readlines }
    Process.kill :INFO, worker_pids.first
    Process.kill :INT , @pid
    t.join

    assert_match "Thread: TID", output.join
  end

  def test_usr2_restart
    _, new_reply = restart_server_and_listen "-q -w#{workers} test/rackup/hello.ru"
    assert_equal "Hello World", new_reply
  end

  # Next two tests, one tcp, one unix
  # Send requests 10 per second.  Send 10, then :TERM server, then send another 30.
  # No more than 10 should throw Errno::ECONNRESET.

  def test_term_closes_listeners_tcp
    skip_unless_signal_exist? :TERM
    term_closes_listeners
  end

  def test_term_closes_listeners_unix
    skip_unless_signal_exist? :TERM
    set_bind_type :unix
    term_closes_listeners
  end

  # Next two tests, one tcp, one unix
  # Send requests 1 per second.  Send 1, then :USR1 server, then send another 24.
  # All should be responded to, and at least three workers should be used

  def test_usr1_all_respond_tcp
    skip_unless_signal_exist? :USR1
    usr1_all_respond
  end

  def test_usr1_fork_worker
    skip_unless_signal_exist? :USR1
    usr1_all_respond config: '--fork-worker'
  end

  def test_usr1_all_respond_unix
    skip_unless_signal_exist? :USR1
    usr1_all_respond
  end

  def test_term_exit_code
    skip_unless_signal_exist? :TERM

    server_spawn "-w#{workers} test/rackup/hello.ru"

    _, status = stop_server

    exit_code = Puma::IS_OSX ? status.to_i : status.exitstatus

    assert_equal 15, exit_code % 128
  end

  def test_term_suppress
    skip_unless_signal_exist? :TERM

    server_spawn "-w#{workers} test/rackup/hello.ru",
      config: "\nraise_exception_on_sigterm false\n"

    _, status = stop_server

    exit_code = Puma::IS_OSX ? status.to_i : status.exitstatus

    assert_equal 0, exit_code % 128
  end

  def test_on_booted
    server_spawn "-w#{workers} test/rackup/hello.ru",  config: <<~CONFIG
      on_booted do
        puts "on_booted called one"
      end

      on_booted do
        puts "on_booted called two"
      end
    CONFIG

    assert wait_for_server_to_include('on_booted called one')
    assert wait_for_server_to_include('on_booted called two')
  end

  def test_term_worker_clean_exit
    skip_unless_signal_exist? :TERM
    server_spawn "-w#{workers} test/rackup/hello.ru"

    # Get the PIDs of the child workers.
    worker_pids = get_worker_pids

    # Signal the workers to terminate, and wait for them to die.
    stop_server

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
    # iso8601 2022-12-14T00:05:49Z
    re_8601 = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/
    set_control_type :tcp
    worker_check_interval = 1

    server_spawn "-w1 -t1:1 test/rackup/hello.ru",
      config: "worker_check_interval #{worker_check_interval}"

    sleep worker_check_interval + 1
    checkin_1 = get_stats["worker_status"].first["last_checkin"]
    assert_match re_8601, checkin_1
    last_checkin_1 = Time.parse checkin_1

    sleep worker_check_interval + 1
    checkin_2 = get_stats["worker_status"].first["last_checkin"]
    assert_match re_8601, checkin_2
    last_checkin_2 = Time.parse checkin_2

    assert(last_checkin_2 > last_checkin_1)
  end

  def test_worker_boot_timeout
    timeout = 1
    worker_timeout(timeout, 2, "failed to boot within \\\d+ seconds", "worker_boot_timeout #{timeout}; on_worker_boot { sleep #{timeout + 1} }")
  end

  def test_worker_timeout
    skip 'Thread#name not available' unless Thread.current.respond_to?(:name)
    timeout = Puma::Configuration::DEFAULTS[:worker_check_interval] + 1
    worker_timeout(timeout, 1, "failed to check in within \\\d+ seconds", <<~CONFIG)
      worker_timeout #{timeout}
      on_worker_boot do
        Thread.new do
          sleep 1
          Thread.list.find { |t| t.name == 'puma stat pld' }.kill
        end
      end
    CONFIG
  end

  def test_idle_timeout
    server_spawn "-w#{workers} test/rackup/hello.ru", config: "idle_timeout 1"

    get_worker_pids # wait for workers to boot

    send_http

    sleep 1.15

    assert_raises Errno::ECONNREFUSED, "Connection refused" do
      send_http
    end
    assert wait_for_server_to_include('Gracefully shutting down workers')
  end

  def test_worker_index_is_with_in_options_limit
    skip_unless_signal_exist? :TERM

    server_spawn "test/rackup/hello.ru", config: <<~'CONFIG'
      pidfile "t3-pid"
      workers 3
      on_worker_boot do |index|
        File.open("t3-worker-#{index}-pid", "w") { |f| f.puts Process.pid }
      end
    CONFIG

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
    refork = unique_path '.refork', contents: ''
    wrkrs = 3
    server_spawn "-w #{wrkrs} test/rackup/hello_with_delay.ru", config: <<~CONFIG
      fork_worker 20
      on_refork { File.write '#{refork}', 'Reforked' }
    CONFIG

    pids = get_worker_pids 0, wrkrs

    refork_io = File.open refork, mode: 'r'
    sockets = []
    until refork_io.read == 'Reforked'
      sockets << send_http
      sleep 0.004
    end

    100.times {
      sockets << send_http
      sleep 0.004
    }

    if ::Puma::IS_OSX # intermittently raises EOFError
      sockets.each do |s|
        begin
          s.read_body
        rescue EOFError
        end
      end
    else
      sockets.each { |s| s.read_body }
    end

    refute_includes pids, get_worker_pids(1, wrkrs - 1)
  ensure
    refork_io&.close
  end

  def test_fork_worker_spawn
    server_spawn '', config: <<~RUBY
      workers 1
      fork_worker 0
      app do |_|
        pid = spawn('ls', [:out, :err]=>'/dev/null')
        sleep 0.01
        exitstatus = Process.detach(pid).value.exitstatus
        [200, {}, [exitstatus.to_s]]
      end
    RUBY
    assert_equal '0', send_http_read_resp_body
  end

  def test_fork_worker_phased_restart_with_high_worker_count
    worker_count = 10

    server_spawn "test/rackup/hello.ru", config: <<~CONFIG
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
    stop_server timeout: 14
  end

  def test_prune_bundler_with_multiple_workers
    server_spawn config: <<~CONFIG
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

    assert_equal "embedded app", send_http_read_resp_body
  end

  def test_load_path_includes_extra_deps
    server_spawn "-w#{workers} test/rackup/hello.ru", config: <<~'CONFIG'
      prune_bundler true
      extra_runtime_dependencies ["minitest"]
      before_fork do
        $LOAD_PATH.each do |path|
          puts "LOAD_PATH: #{path}"
        end
      end
    CONFIG

    get_worker_pids

    assert_match(%r{gems/minitest-[\d.]+/lib$}, @server_log)
  end

  def test_load_path_does_not_include_nio4r
    server_spawn "-w#{workers} test/rackup/hello.ru", config: <<~'CONFIG'
      workers 2
      prune_bundler true
      extra_runtime_dependencies ["minitest"]
      before_fork do
        $LOAD_PATH.each do |path|
          puts "LOAD_PATH: #{path}"
        end
      end
    CONFIG

    get_worker_pids

    refute_match(%r{gems/nio4r-[\d.]+/lib}, @server_log)
  end

  def test_json_gem_not_required_in_master_process
    server_spawn "-w#{workers} test/rackup/hello.ru", config: <<~'CONFIG'
      prune_bundler true
      before_fork do
        puts "defined?(::JSON): #{defined?(::JSON).inspect}"
      end
    CONFIG

    assert wait_for_server_to_match(/defined\?\(::JSON\): nil/)
  end

  def test_nio4r_gem_not_required_in_master_process
    server_spawn "-w#{workers} test/rackup/hello.ru", config: <<~'CONFIG'
      prune_bundler true
      before_fork do
        puts "defined?(::NIO): #{defined?(::NIO).inspect}"
      end
    CONFIG

    assert wait_for_server_to_match(/defined\?\(::NIO\): nil/)
  end

  def test_nio4r_gem_not_required_in_master_process_when_using_control_server
    set_control_type :tcp
    server_spawn "-w#{workers} test/rackup/hello.ru", config: <<~'CONFIG'
      prune_bundler true
      before_fork do
        puts "defined?(::NIO): #{defined?(::NIO).inspect}"
      end
    CONFIG

    assert wait_for_server_to_match(/Starting control server/)

    assert wait_for_server_to_match(/defined\?\(::NIO\): nil/)
  end

  def test_application_is_loaded_exactly_once_if_using_preload_app
    server_spawn "-w#{workers} --preload test/rackup/write_to_stdout_on_boot.ru"

    get_worker_pids

    worker_load_count = @server_log.scan(/^Loading app/).count

    assert_equal 1, worker_load_count
  end

  def test_warning_message_outputted_when_single_worker
    server_spawn "-w 1 test/rackup/hello.ru"

    get_worker_pids 0, 1

    assert_match(/WARNING: Detected running cluster mode with 1 worker/, @server_log)
  end

  def test_warning_message_not_outputted_when_single_worker_silenced
    server_spawn "-w 1 test/rackup/hello.ru", config: "silence_single_worker_warning"

    get_worker_pids 0, 1

    refute_match(/WARNING: Detected running cluster mode with 1 worker/, @server_log)
  end

  def test_signal_ttin
    server_spawn "-w#{workers} test/rackup/hello.ru"
    get_worker_pids 0, 2 # to consume server logs

    Process.kill :TTIN, @pid

    assert wait_for_server_to_match(/Worker 2 \(PID: \d+\) booted in/)
  end

  def test_signal_ttou
    server_spawn "-w#{workers} test/rackup/hello.ru"
    get_worker_pids # to consume server logs

    Process.kill :TTOU, @pid

    assert wait_for_server_to_match(/Worker 1 \(PID: \d+\) terminating/)
  end

  def test_culling_strategy_youngest
    server_spawn "-w#{workers} test/rackup/hello.ru", config: "worker_culling_strategy :youngest"
    get_worker_pids # to consume server logs

    Process.kill :TTIN, @pid

    assert wait_for_server_to_match(/Worker 2 \(PID: \d+\) booted in/)

    Process.kill :TTOU, @pid

    assert wait_for_server_to_match(/Worker 2 \(PID: \d+\) terminating/)
  end

  def test_culling_strategy_oldest
    server_spawn "-w#{workers} test/rackup/hello.ru", config: "worker_culling_strategy :oldest"
    get_worker_pids # to consume server logs

    Process.kill :TTIN, @pid

    assert wait_for_server_to_match(/Worker 2 \(PID: \d+\) booted in/)

    Process.kill :TTOU, @pid

    assert wait_for_server_to_match(/Worker 0 \(PID: \d+\) terminating/)
  end

  def test_culling_strategy_oldest_fork_worker
    server_spawn "-w 2 test/rackup/hello.ru", config: <<~CONFIG
      worker_culling_strategy :oldest
      fork_worker
    CONFIG

    get_worker_pids # to consume server logs

    Process.kill :TTIN, @pid

    assert wait_for_server_to_match(/Worker 2 \(PID: \d+\) booted in/)

    Process.kill :TTOU, @pid

    assert wait_for_server_to_match(/Worker 1 \(PID: \d+\) terminating/)
  end

  def test_hook_data
    skip_unless_signal_exist? :TERM

    file0 = 'hook_data-0.txt'
    file1 = 'hook_data-1.txt'

    server_spawn "-w2 test/rackup/hello.ru", config: <<~'CONFIG'
      on_worker_boot(:test) do |index, data|
        data[:test] = index
      end

      on_worker_shutdown(:test) do |index, data|
        File.write "hook_data-#{index}.txt", "index #{index} data #{data[:test]}", mode: 'wb:UTF-8'
      end
    CONFIG

    get_worker_pids
    stop_server

    # helpful for non MRI Rubies
#    assert wait_for_server_to_include('Goodbye')

    assert_equal 'index 0 data 0', File.read(file0, mode: 'rb:UTF-8')
    assert_equal 'index 1 data 1', File.read(file1, mode: 'rb:UTF-8')

  ensure
    File.unlink file0 if File.file? file0
    File.unlink file1 if File.file? file1
  end

  def test_worker_hook_warning_cli
    server_spawn "-w2 test/rackup/hello.ru", config: <<~CONFIG
      on_worker_boot(:test) do |index, data|
        data[:test] = index
      end
    CONFIG

    get_worker_pids
    line = @server_log[/.+on_worker_boot.+/]
    refute line, "Warning below should not be shown!\n#{line}"
  end

  def test_worker_hook_warning_web_concurrency
    server_spawn "test/rackup/hello.ru",
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
    server_spawn "-w#{workers} test/rackup/hello.ru", puma_debug: true

    assert wait_for_server_to_include('Loaded Extensions - worker 0:')
    assert wait_for_server_to_include('Loaded Extensions - master:')
  end

  private

  def worker_timeout(timeout, iterations, details, config)
    server_spawn "-w#{workers} -t1:1 test/rackup/hello.ru", config: config

    pids = []
    re = /Terminating timed out worker \(Worker \d+ #{details}\): (\d+)/

    loops = workers * iterations

    pids << wait_for_server_to_match(re, 1).to_i while pids.size < loops

    assert_equal pids, pids.uniq
  end

  # Sends 48 requests, 12 per second.  Send 12, then :TERM server, then send another 36.
  def term_closes_listeners
    skip_unless_signal_exist? :TERM
    server_spawn "-w#{workers} -t5:5 -q test/rackup/sleep_pid.ru"
    replies = []
    mutex = Mutex.new
    div   = 12
    reqs  = 4 * div

    refused = thread_run_refused

    queue = Queue.new

    thread_requests = request_ary_thread(reqs, 1.0/div, 1, div, mutex, queue, replies) do
      Process.kill :TERM, @pid
      mutex.synchronize { replies[div] = :term_sent }
    end

    thread_responses = Thread.new do
      collect_response_ary_data(replies, mutex, queue, refused)
    end

    thread_requests.join
    thread_responses.join

    successes     = replies.count { |el| el.is_a? String }
    write_error_classes = replies.select { |el| el.is_a? Class }
    write_errors  = write_error_classes.length
    failures      = replies.count :failure
    resets        = replies.count :reset
    refused       = replies.count :refused
    read_timeouts = replies.count :read_timeout

    r_success   = replies.rindex { |el| el.is_a? String }
    l_write_err = replies.index  { |el| el.is_a? Class }
    l_reset     = replies.index(:reset)

    # tcp sockets Errno::ECONNREFUSED, unix sockets  Errno::ENOENT
    # STDOUT.syswrite "\n#{@bind_type} #{write_error_classes.uniq}\n"

    msg = "#{successes} successes, #{write_errors} write_errors, #{resets} resets, #{refused} refused, #{failures} failures, #{read_timeouts} read timeouts"

    assert_equal 0, failures     , msg
    assert_equal 0, read_timeouts, msg
    assert_equal 0, refused      , msg

    assert_operator (0.20*reqs).to_i, :<=, successes  , msg
    assert_operator (0.10*reqs).to_i, :>=, resets     , msg
    assert_operator (0.65*reqs).to_i, :<=, write_errors, msg

    # Interleaved asserts
    # UNIX binders do not generate :reset items

    assert_operator r_success, :<, l_write_err, "Interleaved success(#{r_success}) and write error (#{l_write_err})"

    if l_reset
      assert_operator r_success, :<, l_reset  , "Interleaved success(#{r_success}) and reset (#{l_reset})"
    end
  ensure
    TestPuma::DEBUGGING_INFO << "#{full_name}\n    #{msg}\n"
    queue&.close
  end

  # Sends 40 requests, 4 per second.  Send 4, then :USR1 server, then send another 36.
  # All should be responded to, and at least three workers should be used
  def usr1_all_respond(config = nil)
    server_spawn "-w#{workers} -t 2:5 -q test/rackup/sleep_pid.ru", config: config
    replies = []
    mutex = Mutex.new
    reqs  = 40

    refused = thread_run_refused

    queue = Queue.new

    thread_requests = request_ary_thread(reqs, 0.25, 1, 4, mutex, queue, replies) do
      Process.kill :USR1, @pid
    end

    thread_responses = Thread.new do
      collect_response_ary_data(replies, mutex, queue, refused)
    end

    thread_requests.join
    thread_responses.join

    responses     = replies.count { |r| r.is_a? String }

    write_error_classes = replies.select { |el| el.is_a? Class }
    write_errors  = write_error_classes.length
    failures      = replies.count :failure

    resets        = replies.count { |r| r == :reset    }
    refused       = replies.count { |r| r == :refused  }
    read_timeouts = replies.count { |r| r == :read_timeout }

    # get pids from replies, generate uniq array
    t = replies.select { |el| el.is_a? String }.map { |body| body[/\d+\z/] }
    t.uniq!; t.compact!
    qty_pids = t.length

    msg = "#{responses} responses, #{qty_pids} uniq pids, #{write_errors} write_errors," \
      "#{resets} resets, #{refused} refused, #{read_timeouts} read timeouts"

    assert_equal reqs, responses, msg
    assert_operator qty_pids, :>, 2, msg

    assert_equal 0, write_errors , msg
    assert_equal 0, failures     , msg
    assert_equal 0, refused      , msg
    assert_equal 0, resets       , msg
    assert_equal 0, read_timeouts, msg

    msg = "#{responses} responses, #{qty_pids} uniq pids"
  ensure
    TestPuma::DEBUGGING_INFO << "#{full_name}\n    #{msg}\n"
    queue&.close
  end

  def worker_respawn(phase = 1, size = workers)
    threads = []

    server_spawn "-w#{workers} -t 1:1 test/rackup/sleep_pid.ru",
      config: "worker_shutdown_timeout 2\n"

    # make sure two workers have booted
    phase0_worker_pids = get_worker_pids

    [35, 40].each do |sleep_time|
      threads << Thread.new do
        begin
          send_http "GET /sleep#{sleep_time} HTTP/1.1\r\n\r\n"
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
  ensure
    threads&.each do |th|
      Thread.kill(th) unless th.join 2
      th = nil
    end
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

  def request_ary_thread(reqs, loop_sleep, app_sleep, blk_idx, mutex, queue, replies, &blk)
    Thread.new do
      req_str = "GET /sleep#{app_sleep} HTTP/1.1\r\n\r\n"
      (reqs + 1).times do |i|
        if i == blk_idx
          yield if blk
        else
          sleep loop_sleep
          begin
            socket = send_http req_str
            queue << [socket, i]
          rescue => e
            mutex.synchronize { replies[i] = e.class }
          end
        end
      end
      queue.close
    end
  end

  def collect_response_ary_data(replies, mutex, queue, refused_errors)
    body_prefix = 'Slept '
    loop do
      break if queue.empty? && queue.closed?
      next unless (val = queue.pop)
      socket, step = val
      begin
        body = socket.read_body
        if body.start_with? body_prefix
          mutex.synchronize { replies[step] = body }
        else
          mutex.synchronize { replies[step] = :failure }
        end
      rescue Errno::ECONNRESET
        # connection was accepted but then closed
        # client would see an empty response
        mutex.synchronize { replies[step] = :reset }
      rescue *refused_errors
        mutex.synchronize { replies[step] = :refused }
      rescue Timeout::Error
        mutex.synchronize { replies[step] = :read_timeout }
      end
    end
  end
end if ::Process.respond_to?(:fork)
