require_relative "helper"
require_relative "helpers/integration"

class TestIntegrationSingle < TestIntegration
  parallelize_me! if ::Puma.mri?

  def workers ; 0 ; end

  def test_hot_restart_does_not_drop_connections_threads
    ttl_reqs = Puma.windows? ? 500 : 1_000
    hot_restart_does_not_drop_connections num_threads: 5, total_requests: ttl_reqs
  end

  def test_hot_restart_does_not_drop_connections
    if Puma.windows?
      hot_restart_does_not_drop_connections total_requests: 300
    else
      hot_restart_does_not_drop_connections
    end
  end

  def test_usr2_restart
    skip_unless_signal_exist? :USR2
    initial_reply, new_reply = restart_server_and_listen("-q test/rackup/hello.ru")
    assert_equal "Hello World", initial_reply
    assert_equal "Hello World", new_reply
  end

  # It does not share environments between multiple generations, which would break Dotenv
  def test_usr2_restart_restores_environment
    # jruby has a bug where setting `nil` into the ENV or `delete` do not change the
    # next workers ENV
    skip_if :jruby
    skip_unless_signal_exist? :USR2

    initial_reply, new_reply = restart_server_and_listen("-q test/rackup/hello-env.ru")

    assert_start_with initial_reply, "Hello RAND"
    assert_start_with new_reply    , "Hello RAND"
    refute_equal initial_reply, new_reply
  end

  def test_term_exit_code
    skip_unless_signal_exist? :TERM
    skip_if :jruby # JVM does not return correct exit code for TERM

    cli_server "test/rackup/hello.ru"
    _, status = stop_server

    assert_equal 15, status
  end

  def test_on_booted_and_on_stopped
    skip_unless_signal_exist? :TERM

    cli_server "-C test/config/event_on_booted_and_on_stopped.rb -C test/config/event_on_booted_exit.rb test/rackup/hello.ru",
      no_wait: true

    assert wait_for_server_to_include('on_booted called')
    assert wait_for_server_to_include('on_stopped called')
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

    body = send_http_read_resp_body
    stop_server

    assert_match("http", body)
  end

  def test_conf_is_loaded_before_passing_it_to_binder
    skip_unless_signal_exist? :TERM

    cli_server("-C test/config/rack_url_scheme.rb test/rackup/url_scheme.ru")

    body = send_http_read_resp_body
    stop_server

    assert_match("https", body)
  end

  def test_prefer_rackup_file_specified_by_cli
    skip_unless_signal_exist? :TERM

    cli_server "-C test/config/with_rackup_from_dsl.rb test/rackup/hello.ru"
    body = send_http_read_resp_body
    stop_server

    assert_match("Hello World", body)
  end

  def test_term_not_accepts_new_connections
    skip_unless_signal_exist? :TERM
    skip_if :jruby

    sleep_time = 8.0

    cli_server '-t1:1 test/rackup/sleep.ru'

    socket = send_http "GET /sleep#{sleep_time} HTTP/1.1\r\n\r\n"
    body = nil
    read_error = nil

    th = Thread.new do
      begin
        body = socket.read_body timeout: 20
      rescue => e
        read_error = e
      end
    end

    # Ruby 2.7 consistent failure, both CI & locally
    sleep 0.05

    Process.kill :TERM, @pid
    Thread.pass

    assert wait_for_server_to_include('Gracefully stopping') # wait for server to begin graceful shutdown

    Thread.pass
    sleep 0.5 # not needed for local testing, but CI runners...

    # Invoke a request which must be rejected
    assert_raises(Errno::ECONNREFUSED, Errno::ECONNRESET) {
      send_http
    }

    refute_nil Process.getpgid(@pid) # ensure server is still running

    th.join
    refute read_error
    assert_equal "Slept #{sleep_time}", body

    wait_server 15
  end

  def test_int_refuse
    skip_unless_signal_exist? :INT
    skip_if :jruby  # seems to intermittently lockup JRuby CI

    cli_server 'test/rackup/hello.ru'
    begin
      new_socket
    rescue => ex
      fail("Port didn't open properly: #{ex.message}")
    end

    Process.kill :INT, @pid
    sleep 0.25
    assert_raises(Errno::ECONNREFUSED) { new_socket }
    wait_server
  end

  def test_siginfo_thread_print
    skip_unless_signal_exist? :INFO

    cli_server 'test/rackup/hello.ru'
    Process.kill :INFO, @pid
    Process.kill :INT , @pid

    assert wait_for_server_to_include("Thread: TID")

    wait_server
  end

  def test_write_to_log
    skip_unless_signal_exist? :TERM

    cli_server '-t1:1 -C test/config/t1_conf.rb test/rackup/hello.ru'

    send_http_read_response
    send_http_read_response # darwin seems to need two requests

    stop_server

    log = File.read('t1-stdout')

    assert_match('GET / HTTP/1.1', log)
  ensure
    File.unlink 't1-stdout' if File.file? 't1-stdout'
    File.unlink 't1-pid'    if File.file? 't1-pid'
  end

  def test_puma_started_log_writing
    skip_unless_signal_exist? :TERM

    cli_server '-t1:1 -C test/config/t2_conf.rb test/rackup/hello.ru'

    out = cli_pumactl '-F test/config/t2_conf.rb status', no_bind: true
    assert_equal("Puma is started\n", out.read)

    send_http_read_response
    send_http_read_response # darwin seems to need two requests

    stop_server

    assert File.file?('t2-stdout')
    log = File.read('t2-stdout')
    assert_match('GET / HTTP/1.1', log)

    refute File.file?("t2-pid")
  ensure
    File.unlink 't2-stdout' if File.file? 't2-stdout'
  end

  def test_application_logs_are_flushed_on_write
    cli_server "#{set_pumactl_args} test/rackup/write_to_stdout.ru"

    send_http_read_response

    cli_pumactl 'stop'

    assert wait_for_server_to_include("hello\n")
    assert wait_for_server_to_include("Goodbye!")

    wait_server
  end

  # listener is closed 'externally' while Puma is in the IO.select statement
  def test_closed_listener
    skip_unless_signal_exist? :TERM

    cli_server "test/rackup/close_listeners.ru", merge_err: true
    socket = send_http

    begin
      socket.read_body
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

    sock = send_http
    assert_equal 'Hello World', sock.read_body

    sleep 1.25

    assert sock.wait_readable(1), 'Unexpected timeout'

    assert_raises(Errno::ECONNREFUSED, "Connection not refused") { new_socket }
    wait_server
  end

  def test_pre_existing_unix_after_idle_timeout
    skip_unless :unix

    File.open(@bind_path, mode: 'wb') { |f| f.puts 'pre existing' }

    cli_server "-q test/rackup/hello.ru", unix: true, config: "idle_timeout 1"

    sock = send_http
    assert_equal 'Hello World', sock.read_body

    sleep 1.15

    assert sock.wait_readable(1), 'Unexpected timeout'

    assert_raises Puma.jruby? ? IOError : Errno::ECONNREFUSED, "Connection not refused" do
      new_socket
    end

    assert File.exist?(@bind_path)
  ensure
    if UNIX_SKT_EXIST
      File.unlink @bind_path if File.exist? @bind_path
      wait_server
    end
  end
end
