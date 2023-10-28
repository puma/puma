# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/test_puma/server_spawn"

class TestIntegrationSingle < TestPuma::ServerSpawn
  parallelize_me! if ::Puma::IS_MRI

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
    _, new_reply = restart_server_and_listen "-q test/rackup/hello.ru"
    assert_equal "Hello World", new_reply
  end

  # It does not share environments between multiple generations, which would break Dotenv
  def test_usr2_restart_restores_environment
    # jruby has a bug where setting `nil` into the ENV or `delete` do not change the
    # next workers ENV
    skip_if :jruby
    skip_unless_signal_exist? :USR2

    initial_reply, new_reply = restart_server_and_listen "-q test/rackup/hello-env.ru"

    assert_includes initial_reply, "Hello RAND"
    assert_includes new_reply, "Hello RAND"
    refute_equal initial_reply, new_reply
  end

  def test_term_exit_code
    skip_unless_signal_exist? :TERM
    skip_if :jruby # some installs work, some don't ???

    server_spawn "test/rackup/hello.ru"

    _, status = stop_server

    exit_code = ::Puma::IS_OSX ? status.to_i : status.exitstatus

    assert_equal 15, exit_code % 128
  end

  def test_on_booted
    server_spawn "test/rackup/hello.ru", config: <<~CONFIG
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

  def test_term_suppress
    skip_unless_signal_exist? :TERM

    server_spawn "test/rackup/hello.ru",
      config: "\nraise_exception_on_sigterm false\n"

    _, status = stop_server

    exit_code = ::Puma::IS_OSX ? status&.to_i : status&.exitstatus

    assert_equal 0, exit_code
  end

  def test_rack_url_scheme_default
    skip_unless_signal_exist? :TERM

    server_spawn("test/rackup/url_scheme.ru")

    body = send_http_read_resp_body
    stop_server

    assert_includes body, "http"
  end

  def test_conf_is_loaded_before_passing_it_to_binder
    skip_unless_signal_exist? :TERM

    server_spawn "test/rackup/url_scheme.ru", config: "rack_url_scheme 'https'"

    body = send_http_read_resp_body
    stop_server

    assert_includes body, "https"
  end

  def test_prefer_rackup_file_specified_by_cli
    skip_unless_signal_exist? :TERM

    server_spawn "test/rackup/hello.ru", config: "rack_url_scheme 'https'"
    body = send_http_read_resp_body
    stop_server

    assert_includes body, "Hello World"
  end

  def test_term_not_accepts_new_connections
    skip_unless_signal_exist? :TERM

    resp_sleep = 8

    server_spawn 'test/rackup/sleep.ru'

    accepted_socket = send_http "GET /sleep#{resp_sleep} HTTP/1.1\r\n\r\n"
    sleep 0.1 # Ruby 2.7 ?
    Process.kill :TERM, @pid
    assert wait_for_server_to_include('Gracefully stopping') # wait for server to begin graceful shutdown

    # listeners are closed after 'Gracefully stopping' is logged
    sleep 0.5

    # Invoke a request which must be rejected, need some time after shutdown
    assert_raises(Errno::ECONNREFUSED) { send_http_read_resp_body }

    assert_includes accepted_socket.read_body, "Slept #{resp_sleep}"
  end

  def test_int_refuse
    skip_unless_signal_exist? :INT
    skip_if :jruby  # seems to intermittently lockup JRuby CI

    server_spawn 'test/rackup/hello.ru'
    begin
      send_http.close
    rescue => ex
      fail("Port didn't open properly: #{ex.message}")
    end

    Process.kill :INT, @pid
    Process.wait @spawn_pid

    assert_raises(Errno::ECONNREFUSED) { new_socket }
  end

  def test_siginfo_thread_print
    skip_unless_signal_exist? :INFO

    server_spawn 'test/rackup/hello.ru'

    Process.kill :INFO, @pid

    assert wait_for_server_to_include('Thread: TID')
  end

  def test_write_to_log
    skip_unless_signal_exist? :TERM

    stdout   = unique_path '.stdout'
    pid_file = unique_path '.pid'

    server_spawn 'test/rackup/hello.ru', config: <<~CONFIG
      log_requests
      stdout_redirect "#{stdout}"
      pidfile "#{pid_file}"
    CONFIG

    2.times { send_http_read_response }

    out = cli_pumactl "-P #{pid_file} status", no_bind: true

    sleep 1.5
    stop_server

    assert File.file?(stdout), "File '#{stdout}' does not exist"
    log = File.read stdout
    assert_includes(log, "GET / HTTP/1.1")
    assert_equal("Puma is started\n", out.read)
    sleep 0.5
    refute File.file?(pid_file)
  end

  def test_puma_started_log_writing
    skip_unless_signal_exist? :TERM

    stdout   = unique_path '.stdout'
    pid_file = unique_path '.pid'

    server_spawn 'test/rackup/hello.ru', config: <<~CONFIG
      log_requests
      stdout_redirect "#{stdout}"
      pidfile "#{pid_file}"
    CONFIG

    2.times { send_http_read_resp_body }

    out = cli_pumactl "-P #{pid_file} status", no_bind: true

    sleep 1.5
    stop_server
    assert File.file?(stdout), "File '#{stdout}' does not exist"
    log = File.read(stdout)

    assert_includes(log, "GET / HTTP/1.1")
    assert_equal("Puma is started\n", out.read)
    sleep 0.5
    refute File.file?(pid_file)
  end

  def test_application_logs_are_flushed_on_write
    set_control_type :tcp
    server_spawn "test/rackup/write_to_stdout.ru"

    send_http_read_resp_body

    cli_pumactl 'stop'

    assert wait_for_server_to_include("hello\n")
    assert wait_for_server_to_include('Goodbye')

  ensure
    @server = nil if ::Puma::IS_WINDOWS # see ServerSpawn#after_teardown
  end

  # listener is closed 'externally' while Puma is in the IO.select statement
  def test_closed_listener
    skip_unless_signal_exist? :TERM

    server_spawn "test/rackup/close_listeners.ru"
    if Puma::IS_JRUBY
      assert_includes send_http_read_response, "HTTP/1.1 500 Internal Server"
    else
      assert_includes send_http_read_response, "#<TCPServer:(closed)>"
    end

    begin
      Timeout.timeout(5) { kill_and_wait @pid }
    rescue Timeout::Error
      Process.kill :SIGKILL, @pid
      assert false, "Process froze"
    end
    assert true
  end

  def test_puma_debug_loaded_exts
    set_control_type :tcp
    server_spawn "test/rackup/hello.ru", puma_debug: true

    assert wait_for_server_to_include('Loaded Extensions:')

    cli_pumactl 'stop'
    assert wait_for_server_to_include('Goodbye')

  ensure
    @server = nil if ::Puma::IS_WINDOWS # see ServerSpawn#after_teardown
  end

  def test_idle_timeout
    server_spawn "test/rackup/hello.ru", config: "idle_timeout 1"

    send_http

    sleep 1.15

    assert_raises Errno::ECONNREFUSED, "Connection refused" do
      send_http
    end
  end

  def test_pre_existing_unix_after_idle_timeout
    set_bind_type :unix

    File.write bind_path, 'pre existing', mode: 'wb'

    server_spawn "-q test/rackup/hello.ru", config: "idle_timeout 1"

    socket = send_http

    sleep 1.15

    assert socket.wait_readable(1), 'Unexpected timeout'
    assert_raises Puma.jruby? ? IOError : Errno::ECONNREFUSED, "Connection refused" do
      send_http
    end

    assert File.exist?(bind_path)
  ensure
    if UNIX_SKT_EXIST
      File.unlink bind_path if File.exist? bind_path
    end
  end
end
