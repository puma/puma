# frozen_string_literal: true

require_relative "helper"
require "puma/control_cli"
require "open3"

class TestIntegration < Minitest::Test
  parallelize_me!

  HOST  = "127.0.0.1"
  TOKEN = "xxyyzz"

  BASE = defined?(Bundler) ? "bundle exec #{Gem.ruby} -Ilib" :
    "#{Gem.ruby} -Ilib"

  WORKERS = 2

  def setup
    @ios_to_close = []
    @state_path   = "test/#{name}_puma.state"
    @bind_path    = "test/#{name}_server.sock"
    @control_path = "test/#{name}_control.sock"
  end

  def teardown
    if defined?(@server) && @server
      begin
        Process.kill :INT, @server.pid
      rescue Errno::ESRCH
      end
      begin
        Process.wait @pid
      rescue Errno::ECHILD
      end
      @server.close unless @server.closed?
      @server = nil
    end

    @ios_to_close.each do |io|
      io.close if io.is_a?(IO) && !io.closed?
      io = nil
    end

    File.unlink @state_path   rescue nil
    File.unlink @bind_path    rescue nil
    File.unlink @control_path rescue nil
  end

  def test_pumactl_stop
    skip UNIX_SKT_MSG unless UNIX_SKT_EXIST
    cli_server "-q test/rackup/sleep.ru --control-url unix://#{@control_path} --control-token #{TOKEN} -S #{@state_path}"

    cli_pumactl "stop", unix: true

    _, status = Process.wait2 @pid
    assert_equal 0, status

    @server = nil
  end

  def test_pumactl_phased_restart_cluster
    skip NO_FORK_MSG unless HAS_FORK

    cli_server "-q -w #{WORKERS} test/rackup/sleep.ru --control-url unix://#{@control_path} --control-token #{TOKEN} -S #{@state_path}", unix: true

    s = UNIXSocket.new @bind_path
    @ios_to_close << s
    s << "GET /sleep5 HTTP/1.0\r\n\r\n"

    # Get the PIDs of the phase 0 workers.
    phase0_worker_pids = get_worker_pids 0

    # Phased restart
    cli_pumactl "phased-restart", unix: true

    # Get the PIDs of the phase 1 workers.
    phase1_worker_pids = get_worker_pids 1

    msg = "phase 0 pids #{phase0_worker_pids.inspect}  phase 1 pids #{phase1_worker_pids.inspect}"

    assert_equal WORKERS, phase0_worker_pids.length, msg
    assert_equal WORKERS, phase1_worker_pids.length, msg
    assert_empty phase0_worker_pids & phase1_worker_pids, "#{msg}\nBoth workers should be replaced with new"

    # Stop
    cli_pumactl "stop", unix: true

    _, status = Process.wait2 @pid
    assert_equal 0, status

    @server = nil
  end

  def test_pumactl_kill_unknown
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

  def test_usr2_restart_single
    skip_unless_signal_exist? :USR2
    _, new_reply = restart_server_and_listen("-q test/rackup/hello.ru")
    assert_equal "Hello World", new_reply
  end

  def test_usr2_restart_cluster
    skip NO_FORK_MSG unless HAS_FORK
    _, new_reply = restart_server_and_listen("-q -w #{WORKERS} test/rackup/hello.ru")
    assert_equal "Hello World", new_reply
  end

  # It does not share environments between multiple generations, which would break Dotenv
  def test_usr2_restart_restores_environment
    # jruby has a bug where setting `nil` into the ENV or `delete` do not change the
    # next workers ENV
    skip_on :jruby
    skip_unless_signal_exist? :USR2

    initial_reply, new_reply = restart_server_and_listen("-q test/rackup/hello-env.ru")

    assert_includes initial_reply, "Hello RAND"
    assert_includes new_reply, "Hello RAND"
    refute_equal initial_reply, new_reply
  end

  # Send requests 10 per second.  Send 10, then :TERM server, then send another 30.
  # No more than 10 should throw Errno::ECONNRESET.
  def test_term_closes_listeners_cluster
    skip NO_FORK_MSG unless HAS_FORK
    skip_unless_signal_exist? :TERM

    cli_server "-w #{WORKERS} -t 0:6 -q test/rackup/sleep_pid.ru"
    threads = []
    replies = []
    mutex = Mutex.new
    div   = 10

    41.times.each do |i|
      if i == 10
        threads << Thread.new do
          sleep i.to_f/div
          Process.kill :TERM, @pid
          mutex.synchronize { replies << :term_sent }
        end
      else
        threads << Thread.new do
          thread_run replies, i.to_f/div, 1, mutex
        end
      end
    end

    threads.each(&:join)

    responses = replies.count { |r| r[/\ASlept 1/] }
    resets    = replies.count { |r| r == :reset    }
    refused   = replies.count { |r| r == :refused  }
    msg = "#{responses} responses, #{resets} resets, #{refused} refused"

    assert_operator 9,  :<=, responses, msg

    assert_operator 10, :>=, resets   , msg

    assert_operator 20, :<=, refused  , msg
  end

  # Send requests 1 per second.  Send 1, then :USR1 server, then send another 24.
  # All should be responded to, and at least three workers should be used
  def test_usr1_all_respond_cluster
    skip NO_FORK_MSG unless HAS_FORK
    skip_unless_signal_exist? :USR1

    cli_server "-w #{WORKERS} -t 0:5 -q test/rackup/sleep_pid.ru"
    threads = []
    replies = []
    mutex = Mutex.new

    s = connect "sleep1"
    replies << read_body(s)
    Process.kill :USR1, @pid

    24.times do |delay|
      threads << Thread.new do
        thread_run replies, delay, 1, mutex
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
  end

  def test_term_exit_code_single
    skip_unless_signal_exist? :TERM

    cli_server "test/rackup/hello.ru"
    _, status = stop_server

    assert_equal 15, status
  end

  def test_term_exit_code_cluster
    skip NO_FORK_MSG unless HAS_FORK

    cli_server "-w #{WORKERS} test/rackup/hello.ru"
    _, status = stop_server

    assert_equal 15, status
  end

  def test_term_suppress_single
    skip_unless_signal_exist? :TERM

    cli_server "-C test/config/suppress_exception.rb test/rackup/hello.ru"
    _, status = stop_server

    assert_equal 0, status
  end

  def test_term_suppress_cluster
    skip NO_FORK_MSG unless HAS_FORK

    cli_server "-w #{WORKERS} -C test/config/suppress_exception.rb test/rackup/hello.ru"

    Process.kill :TERM, @pid
    begin
      Process.wait @pid
    rescue Errno::ECHILD
    end
    status = $?.exitstatus

    assert_equal 0, status
    @server.close unless @server.closed?
    @server = nil # prevent `#teardown` from killing already killed server
  end

  def test_load_path_includes_extra_deps
    skip NO_FORK_MSG unless HAS_FORK

    cli_server "-w 2 -C test/config/prune_bundler_with_deps.rb test/rackup/hello-last-load-path.ru"

    last_load_path = read_body(connect)
    assert_match(%r{gems/rdoc-[\d.]+/lib$}, last_load_path)
  end

  def test_term_not_accepts_new_connections
    skip_unless_signal_exist? :TERM
    skip_on :jruby

    cli_server 'test/rackup/sleep.ru'

    _stdin, curl_stdout, _stderr, curl_wait_thread = Open3.popen3("curl http://#{HOST}:#{@tcp_port}/sleep10")
    sleep 1 # ensure curl send a request

    Process.kill :TERM, @pid
    true while @server.gets !~ /Gracefully stopping/ # wait for server to begin graceful shutdown

    # Invoke a request which must be rejected
    _stdin, _stdout, rejected_curl_stderr, rejected_curl_wait_thread = Open3.popen3("curl #{HOST}:#{@tcp_port}")

    refute_nil Process.getpgid(@pid) # ensure server is still running
    refute_nil Process.getpgid(rejected_curl_wait_thread[:pid]) # ensure first curl invokation still in progress

    curl_wait_thread.join
    rejected_curl_wait_thread.join

    assert_match(/Slept 10/, curl_stdout.read)
    assert_match(/Connection refused/, rejected_curl_stderr.read)

    Process.wait @pid
    @server.close unless @server.closed?
    @server = nil # prevent `#teardown` from killing already killed server
  end

  def test_term_worker_clean_exit_cluster
    skip NO_FORK_MSG unless HAS_FORK
    skip_unless_signal_exist? :TERM
    skip "Intermittent failure on Ruby 2.2" if RUBY_VERSION < '2.3'

    cli_server "-w #{WORKERS} test/rackup/hello.ru"

    # Get the PIDs of the child workers.
    worker_pids = get_worker_pids 0

    # Signal the workers to terminate, and wait for them to die.
    Process.kill :TERM, @pid
    Process.wait @pid

    zombies = bad_exit_pids worker_pids

    assert_empty zombies, "Process ids #{zombies} became zombies"
  end

  # mimicking stuck workers, test respawn with external TERM
  def test_stuck_external_term_spawn_cluster
    skip_unless_signal_exist? :TERM

    worker_respawn(0) do |phase0_worker_pids|
      last = phase0_worker_pids.last
      phase0_worker_pids.each do |pid|
        Process.kill :TERM, pid
        sleep 4 unless pid == last
      end
    end
  end

  # mimicking stuck workers, test restart
  def test_stuck_phased_restart_cluster
    skip_unless_signal_exist? :USR1
    worker_respawn { |phase0_worker_pids| Process.kill :USR1, @pid }
  end

  private

  def cli_server(argv, unix: false)
    if unix
      cmd = "#{BASE} bin/puma -b unix://#{@bind_path} #{argv}"
    else
      @tcp_port = UniquePort.call
      cmd = "#{BASE} bin/puma -b tcp://#{HOST}:#{@tcp_port} #{argv}"
    end
    @server = IO.popen(cmd, "r")
    wait_for_server_to_boot
    @pid = @server.pid
    @server
  end

  def stop_server(pid = @pid, signal: :TERM)
    Process.kill signal, pid
    sleep 1
    begin
      Process.wait2 pid
    rescue Errno::ECHILD
    end
  end

  def restart_server_and_listen(argv)
    cli_server argv
    connection = connect
    initial_reply = read_body(connection)
    restart_server(connection)
    [initial_reply, read_body(connect)]
  end

  # reuses an existing connection to make sure that works
  def restart_server(connection)
    Process.kill :USR2, @pid
    connection.write "GET / HTTP/1.1\r\n\r\n" # trigger it to start by sending a new request
    wait_for_server_to_boot
  end

  def wait_for_server_to_boot
    true while @server.gets !~ /Ctrl-C/ # wait for server to say it booted
  end

  def connect(path = nil, unix: false)
    s = unix ? UNIXSocket.new("unix://#{@bind_path}") : TCPSocket.new(HOST, @tcp_port)
    @ios_to_close << s
    s << "GET /#{path} HTTP/1.1\r\n\r\n"
    true until s.gets == "\r\n"
    s
  end

  def read_body(connection)
    Timeout.timeout(10) do
      loop do
        response = connection.readpartial(1024)
        body = response.split("\r\n\r\n", 2).last
        return body if body && !body.empty?
        sleep 0.01
      end
    end
  end

  def cli_pumactl(argv, unix: false)
    if unix
      pumactl = IO.popen("#{BASE} bin/pumactl -C unix://#{@control_path} -T #{TOKEN} #{argv}", "r")
    else
      pumactl = IO.popen("#{BASE} bin/pumactl #{argv}", "r")
    end
    @ios_to_close << pumactl
    Process.wait pumactl.pid
    pumactl
  end

  def worker_respawn(phase = 1, size = WORKERS)
    skip NO_FORK_MSG unless HAS_FORK
    threads = []

    cli_server "-w #{WORKERS} -t 1:1 -C test/config/worker_shutdown_timeout_2.rb test/rackup/sleep_pid.ru"

    # make sure two workers have booted
    phase0_worker_pids = get_worker_pids 0

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
    stop_server signal: :KILL
  end

  # gets worker pids from @server output
  # new workers created from 'phased-restart' increment phase
  # new workers created from externally shutdown pids maintain same phase
  def get_worker_pids(phase = 1, size = WORKERS)
    pids = []
    re = /pid: (\d+)\) booted, phase: #{phase}/
    while pids.size < size
      line = @server.gets          # line variable left for debugging
      if pid = line[re, 1]
        pids << pid
      else
        sleep 2
      end
    end
    pids.map(&:to_i)
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

  def thread_run(replies, delay, sleep_time, mutex, unix: false)
    begin
      sleep delay
      s = connect "sleep#{sleep_time}", unix: unix
      body = read_body(s)
      mutex.synchronize { replies << body }
    rescue Errno::ECONNRESET
      # connection was accepted but then closed
      # client would see an empty response
      mutex.synchronize { replies << :reset }
    rescue Errno::ECONNREFUSED, Errno::EPIPE
      # TCP  - Errno::ECONNREFUSED, Errno::EPIPE
      # TODO UNIX
      # connection was never accepted it can therefore be
      # re-tried before the client receives an empty response
      mutex.synchronize { replies << :refused }
    end
  end
end
