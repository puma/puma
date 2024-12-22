require_relative "helper"
require_relative "helpers/integration"

class TestIntegrationSingle < TestIntegration
  parallelize_me! if ::Puma.mri?

  def workers ; 0 ; end

  def test_hot_restart_does_not_drop_connections_threads
    ttl_reqs = Puma.windows? ? 500 : 1_000
    restart_does_not_drop_connections num_threads: 5, total_requests: ttl_reqs,
      signal: :USR2
  end

  def test_hot_restart_does_not_drop_connections
    if Puma.windows?
      restart_does_not_drop_connections total_requests: 300,
        signal: :USR2
    else
      restart_does_not_drop_connections signal: :USR2
    end
  end

  def test_usr2_restart
    skip_unless_signal_exist? :USR2
    _, new_reply = restart_server_and_listen("-q test/rackup/hello.ru")
    assert_equal "Hello World", new_reply
  end

  # It does not share environments between multiple generations, which would break Dotenv
  def test_usr2_restart_restores_environment
    # jruby has a bug where setting `nil` into the ENV or `delete` do not change the
    # next workers ENV
    skip_if :jruby
    skip_unless_signal_exist? :USR2

    initial_reply, new_reply = restart_server_and_listen("-q test/rackup/hello-env.ru")

    assert_includes initial_reply, "Hello RAND"
    assert_includes new_reply, "Hello RAND"
    refute_equal initial_reply, new_reply
  end

  def test_term_exit_code
    skip_unless_signal_exist? :TERM
    skip_if :jruby # JVM does not return correct exit code for TERM

    cli_server "test/rackup/hello.ru"
    _, status = stop_server

    assert_equal 15, status
  end

  def test_after_booted_and_after_stopped
    skip_unless_signal_exist? :TERM

    cli_server "-C test/config/event_after_booted_and_after_stopped.rb -C test/config/event_after_booted_exit.rb test/rackup/hello.ru",
      no_wait: true

    assert wait_for_server_to_include('after_booted called')
    assert wait_for_server_to_include('after_stopped called')
  end

  def test_term_suppress
    skip_unless_signal_exist? :TERM

    cli_server "-C test/config/suppress_exception.rb test/rackup/hello.ru"
    _, status = stop_server

    assert_equal 0, status
  end

  def test_rack_url_scheme_default
    skip_unless_signal_exist? :TERM

    cli_server("test/rackup/url_scheme.ru")

    reply = read_body(connect)
    stop_server

    assert_match("http", reply)
  end

  def test_conf_is_loaded_before_passing_it_to_binder
    skip_unless_signal_exist? :TERM

    cli_server("-C test/config/rack_url_scheme.rb test/rackup/url_scheme.ru")

    reply = read_body(connect)
    stop_server

    assert_match("https", reply)
  end

  def test_prefer_rackup_file_specified_by_cli
    skip_unless_signal_exist? :TERM

    cli_server "-C test/config/with_rackup_from_dsl.rb test/rackup/hello.ru"
    reply = read_body(connect)
    stop_server

    assert_match("Hello World", reply)
  end

  def test_term_not_accepts_new_connections
    skip_unless_signal_exist? :TERM
    skip_if :jruby

    cli_server 'test/rackup/sleep.ru'

    _stdin, curl_stdout, _stderr, curl_wait_thread = Open3.popen3({ 'LC_ALL' => 'C' }, "curl http://#{HOST}:#{@tcp_port}/sleep10")
    sleep 1 # ensure curl send a request

    Process.kill :TERM, @pid
    assert wait_for_server_to_include('Gracefully stopping') # wait for server to begin graceful shutdown

    # Invoke a request which must be rejected
    _stdin, _stdout, rejected_curl_stderr, rejected_curl_wait_thread = Open3.popen3("curl #{HOST}:#{@tcp_port}")

    assert nil != Process.getpgid(@server.pid) # ensure server is still running
    assert nil != Process.getpgid(curl_wait_thread[:pid]) # ensure first curl invocation still in progress

    curl_wait_thread.join
    rejected_curl_wait_thread.join

    assert_match(/Slept 10/, curl_stdout.read)
    assert_match(/Connection refused|(Couldn't|Could not) connect to server/, rejected_curl_stderr.read)

    wait_server 15
  end

  def test_int_refuse
    skip_unless_signal_exist? :INT
    skip_if :jruby  # seems to intermittently lockup JRuby CI

    cli_server 'test/rackup/hello.ru'
    begin
      sock = TCPSocket.new(HOST, @tcp_port)
      sock.close
    rescue => ex
      fail("Port didn't open properly: #{ex.message}")
    end

    Process.kill :INT, @pid
    wait_server

    assert_raises(Errno::ECONNREFUSED) { TCPSocket.new(HOST, @tcp_port) }
  end

  def test_siginfo_thread_print
    skip_unless_signal_exist? :INFO

    cli_server 'test/rackup/hello.ru'
    output = []
    t = Thread.new { output << @server.readlines }
    Process.kill :INFO, @pid
    Process.kill :INT , @pid
    t.join

    assert_match "Thread: TID", output.join
  end

  def test_write_to_log
    skip_unless_signal_exist? :TERM

    suppress_output = '> /dev/null 2>&1'

    cli_server '-C test/config/t1_conf.rb test/rackup/hello.ru'

    system "curl http://localhost:#{@tcp_port}/ #{suppress_output}"

    stop_server

    log = File.read('t1-stdout')

    assert_match(%r!GET / HTTP/1\.1!, log)
  ensure
    File.unlink 't1-stdout' if File.file? 't1-stdout'
    File.unlink 't1-pid'    if File.file? 't1-pid'
  end

  def test_puma_started_log_writing
    skip_unless_signal_exist? :TERM

    cli_server '-C test/config/t2_conf.rb test/rackup/hello.ru'

    system "curl http://localhost:#{@tcp_port}/ > /dev/null 2>&1"

    out=`#{BASE} bin/pumactl -F test/config/t2_conf.rb status`

    stop_server

    log = File.read('t2-stdout')

    assert_match(%r!GET / HTTP/1\.1!, log)
    assert(!File.file?("t2-pid"))
    assert_equal("Puma is started\n", out)
  ensure
    File.unlink 't2-stdout' if File.file? 't2-stdout'
  end

  def test_application_logs_are_flushed_on_write
    cli_server "#{set_pumactl_args} test/rackup/write_to_stdout.ru"

    read_body connect

    cli_pumactl 'stop'

    assert wait_for_server_to_include("hello\n")
    assert wait_for_server_to_include("Goodbye!")

    wait_server
  end

  # listener is closed 'externally' while Puma is in the IO.select statement
  def test_closed_listener
    skip_unless_signal_exist? :TERM

    cli_server "test/rackup/close_listeners.ru", merge_err: true
    connection = fast_connect

    begin
      read_body connection
    rescue EOFError
    end

    begin
      Timeout.timeout(5) do
        begin
          Process.kill :SIGTERM, @pid
        rescue Errno::ESRCH
        end
        begin
          Process.wait2 @pid
        rescue Errno::ECHILD
        end
      end
    rescue Timeout::Error
      Process.kill :SIGKILL, @pid
      assert false, "Process froze"
    end
    assert true
  end

  def test_puma_debug_loaded_exts
    cli_server "#{set_pumactl_args} test/rackup/hello.ru", puma_debug: true

    assert wait_for_server_to_include('Loaded Extensions:')

    cli_pumactl 'stop'
    assert wait_for_server_to_include('Goodbye!')
    wait_server
  end

  def test_idle_timeout
    cli_server "test/rackup/hello.ru", config: "idle_timeout 1"

    connect

    sleep 1.15

    assert_raises Errno::ECONNREFUSED, "Connection refused" do
      connect
    end
  end

  def test_pre_existing_unix_after_idle_timeout
    skip_unless :unix

    File.open(@bind_path, mode: 'wb') { |f| f.puts 'pre existing' }

    cli_server "-q test/rackup/hello.ru", unix: :unix, config: "idle_timeout 1"

    sock = connection = connect(nil, unix: true)
    read_body(connection)

    sleep 1.15

    assert sock.wait_readable(1), 'Unexpected timeout'
    assert_raises Puma.jruby? ? IOError : Errno::ECONNREFUSED, "Connection refused" do
      connection = connect(nil, unix: true)
    end

    assert File.exist?(@bind_path)
  ensure
    if UNIX_SKT_EXIST
      File.unlink @bind_path if File.exist? @bind_path
    end
  end
end
