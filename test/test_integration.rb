# frozen_string_literal: true

require_relative "helper"
require "puma/cli"
require "puma/control_cli"
require "open3"

class TestIntegration < Minitest::Test
  TOKEN = "xxyyzz"

  def setup
    @wait, @ready = IO.pipe

    @events = Puma::Events.strings
    @events.on_booted { @ready << "!" }
  end

  def teardown
    File.unlink state_path if File.exist?(state_path)
    File.unlink bind_path if File.exist?(bind_path)
    File.unlink control_path if File.exist?(control_path)

    @wait.close
    @ready.close

    stop_server if @server
  end

  def test_stop_via_pumactl
    skip UNIX_SKT_MSG unless UNIX_SKT_EXIST

    conf = Puma::Configuration.new do |c|
      c.quiet
      c.state_path state_path
      c.bind "unix://#{bind_path}"
      c.activate_control_app "unix://#{control_path}", :auth_token => TOKEN
      c.rackup "test/rackup/hello.ru"
    end

    t = Thread.new { Puma::Launcher.new(conf, :events => @events).run }

    wait_booted

    s = UNIXSocket.new bind_path
    s << "GET / HTTP/1.0\r\n\r\n"
    assert_equal "Hello World", read_body(s)

    Puma::ControlCLI.new(%W!-S #{state_path} stop!, StringIO.new).run

    assert_kind_of Thread, t.join, "server didn't stop"
  end

  def test_phased_restart_via_pumactl
    skip "Test causes tests to run twice"
    skip NO_FORK_MSG unless HAS_FORK
    skip UNIX_SKT_MSG unless UNIX_SKT_EXIST

    # The intention of this test is to get a worker "stuck" sleeping and
    # then force a phased restart via pumactl. This is why worker_shutdown_timeout is
    # set to 2.
    delay = 999

    conf = Puma::Configuration.new do |c|
      c.quiet
      c.state_path state_path
      c.bind "unix://#{bind_path}"
      c.activate_control_app "unix://#{control_path}", :auth_token => TOKEN
      c.workers 2
      c.worker_shutdown_timeout 2
      c.rackup "test/rackup/sleep.ru"
    end

    l = Puma::Launcher.new conf, :events => @events

    t = Thread.new do
      l.run
    end

    wait_booted

    s = UNIXSocket.new bind_path
    s << "GET /sleep#{delay} HTTP/1.0\r\n\r\n"

    sout = StringIO.new
    # Phased restart
    ccli = Puma::ControlCLI.new ["-S", state_path, "phased-restart"], sout
    ccli.run

    done = false
    until done
      @events.stdout.rewind
      log = @events.stdout.readlines.join("")
      if log =~ /- Worker \d \(pid: \d+\) booted, phase: 1/
        assert_match(/TERM sent/, log)
        assert_match(/- Worker \d \(pid: \d+\) booted, phase: 1/, log)
        done = true
      end
    end
    # Stop
    ccli = Puma::ControlCLI.new ["-S", state_path, "stop"], sout
    ccli.run

    assert_kind_of Thread, t.join, "server didn't stop"
    assert File.exist? bind_path
  end

  def test_kill_unknown_via_pumactl
    skip_on :jruby

    # we run ls to get a 'safe' pid to pass off as puma in cli stop
    # do not want to accidentally kill a valid other process
    io = IO.popen(windows? ? "dir" : "ls")
    safe_pid = io.pid
    Process.wait safe_pid

    sout = StringIO.new

    e = assert_raises SystemExit do
      ccli = Puma::ControlCLI.new %W!-p #{safe_pid} stop!, sout
      ccli.run
    end
    sout.rewind
    # windows bad URI(is not URI?)
    assert_match(/No pid '\d+' found|bad URI\(is not URI\?\)/, sout.readlines.join(""))
    assert_equal(1, e.status)
  end

  def test_restart_with_usr2_works
    skip_unless_signal_exist? :USR2
    _, new_reply = restart_server_and_listen("-q test/rackup/hello.ru")
    assert_equal "Hello World", new_reply
  end

  def test_restart_with_usr2_works_workers
    skip NO_FORK_MSG unless HAS_FORK
    _, new_reply = restart_server_and_listen("-q -w 2 test/rackup/hello.ru")
    assert_equal "Hello World", new_reply
  end

  def test_sigterm_closes_listeners_on_forked_servers
    skip NO_FORK_MSG unless HAS_FORK
    pid = server("-w 2 -q test/rackup/sleep.ru").pid
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
          s = connect
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

    threads.map(&:join)

    assert_equal "Slept 1", initial_reply

    assert_includes next_replies, :connection_refused

    refute_includes next_replies, :connection_reset
  end

  # It does not share environments between multiple generations, which would break Dotenv
  def test_restart_restores_environment
    # jruby has a bug where setting `nil` into the ENV or `delete` do not change the
    # next workers ENV
    skip_on :jruby
    skip_unless_signal_exist? :USR2

    initial_reply, new_reply = restart_server_and_listen("-q test/rackup/hello-env.ru")

    assert_includes initial_reply, "Hello RAND"
    assert_includes new_reply, "Hello RAND"
    refute_equal initial_reply, new_reply
  end

  def test_term_signal_exit_code_in_single_mode
    server("test/rackup/hello.ru")
    _, status = stop_server

    assert_equal 15, status
  end

  def test_term_signal_exit_code_in_clustered_mode
    skip NO_FORK_MSG unless HAS_FORK

    server("-w 2 test/rackup/hello.ru")
    _, status = stop_server

    assert_equal 15, status
  end

  def test_term_signal_suppress_in_single_mode
    server("-C test/config/suppress_exception.rb test/rackup/hello.ru")
    _, status = stop_server

    assert_equal 0, status
  end

  def test_term_signal_suppress_in_clustered_mode
    skip NO_FORK_MSG unless HAS_FORK

    server("-w 2 -C test/config/suppress_exception.rb test/rackup/hello.ru")
    _, status = stop_server

    assert_equal 0, status
  end

  def test_not_accepts_new_connections_after_term_signal
    skip_on :jruby, :windows

    server_under_test = server('test/rackup/sleep.ru')

    _stdin, curl_stdout, _stderr, curl_wait_thread = Open3.popen3("curl http://127.0.0.1:#{@tcp_port}/sleep10")
    sleep 1 # ensure curl send a request

    Process.kill(:TERM, server_under_test.pid)
    true while server_under_test.gets !~ /Gracefully stopping/ # wait for server to begin graceful shutdown

    # Invoke a request which must be rejected
    _stdin, _stdout, rejected_curl_stderr, rejected_curl_wait_thread = Open3.popen3("curl 127.0.0.1:#{@tcp_port}")

    assert nil != Process.getpgid(server_under_test.pid) # ensure server is still running
    assert nil != Process.getpgid(rejected_curl_wait_thread[:pid]) # ensure first curl invokation still in progress

    curl_wait_thread.join
    rejected_curl_wait_thread.join

    assert_match(/Slept 10/, curl_stdout.read)
    assert_match(/Connection refused/, rejected_curl_stderr.read)

    Process.wait(server_under_test.pid)
    @server = nil # prevent `#teardown` from killing already killed server
  end

  def test_no_zombie_children
    skip NO_FORK_MSG unless HAS_FORK
    skip "Intermittent failure on Ruby 2.2" if RUBY_VERSION < '2.3'

    worker_pids = []
    server_under_test = server("-w 2 test/rackup/hello.ru")
    # Get the PIDs of the child workers.
    while worker_pids.size < 2
      next unless line = server_under_test.gets.match(/pid: (\d+)/)
      worker_pids << line.captures.first.to_i
    end

    stop_server

    # Check if the worker processes remain in the process table.
    # Process.kill should raise the Errno::ESRCH exception,
    # indicating the process is dead and has been reaped.
    zombies = worker_pids.map do |pid|
      begin
        pid if Process.kill 0, pid
      rescue Errno::ESRCH
        nil
      end
    end.compact
    assert_empty zombies, "Process ids #{zombies} became zombies"
  end

  private

  def test_method_name
    @test_method_name ||= begin
      test_method = caller.detect { |l| l.match(/in `(test_.*)/) }
      test_method = /in `(test_.*)'/.match(test_method)
      test_method && test_method[1]
    end
  end

  def server_cmd(argv)
    @tcp_port = UniquePort.call
    base = "#{Gem.ruby} -Ilib bin/puma"
    base = "bundle exec #{base}" if defined?(Bundler)

    "#{base} -b tcp://127.0.0.1:#{@tcp_port} --tag '#{test_method_name}' #{argv}"
  end

  def server(argv)
    @server ||= begin
      s = IO.popen(server_cmd(argv), "r")
      wait_for_server_to_boot(s)
      s
    end
  end

  def stop_server
    Process.kill(:TERM, @server.pid)
    pid_and_status = Process.wait2(@server.pid)
    @server = nil
    pid_and_status
  end

  def restart_server_and_listen(argv)
    server_under_test = server(argv)
    connection = connect
    initial_reply = read_body(connection)
    restart_server(server_under_test, connection)
    [initial_reply, read_body(connect)]
  end

  def wait_booted
    @wait.sysread 1
  end

  # reuses an existing connection to make sure that works
  def restart_server(server, connection)
    Process.kill :USR2, server.pid

    connection.write "GET / HTTP/1.1\r\n\r\n" # trigger it to start by sending a new request

    wait_for_server_to_boot(server)
  end

  def wait_for_server_to_boot(server)
    true while server.gets !~ /Ctrl-C/ # wait for server to say it booted
  end

  def connect(path = nil)
    s = TCPSocket.new "localhost", @tcp_port
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

  def state_path
    return "" unless test_method_name
    "test/#{test_method_name}_puma.state"
  end

  def bind_path
    return "" unless test_method_name
    "test/#{test_method_name}_server.sock"
  end

  def control_path
    return "" unless test_method_name
    "test/#{test_method_name}_control.sock"
  end
end
