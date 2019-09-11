require_relative "helper"
require_relative "helpers/integration"

class TestIntegrationSingle < TestIntegration
  def test_usr2_restart
    skip_unless_signal_exist? :USR2
    _, new_reply = restart_server_and_listen("-q test/rackup/hello.ru")
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

  def test_term_exit_code
    skip_on :windows # no SIGTERM

    pid = cli_server("test/rackup/hello.ru").pid
    _, status = send_term_to_server(pid)

    assert_equal 15, status
  end

  def test_term_suppress
    skip_on :windows # no SIGTERM

    pid = cli_server("-C test/config/suppress_exception.rb test/rackup/hello.ru").pid
    _, status = send_term_to_server(pid)

    assert_equal 0, status
  end

  def test_term_not_accepts_new_connections
    skip_on :jruby, :windows

    cli_server('test/rackup/sleep.ru')

    _stdin, curl_stdout, _stderr, curl_wait_thread = Open3.popen3("curl http://#{HOST}:#{@tcp_port}/sleep10")
    sleep 1 # ensure curl send a request

    Process.kill(:TERM, @server.pid)
    true while @server.gets !~ /Gracefully stopping/ # wait for server to begin graceful shutdown

    # Invoke a request which must be rejected
    _stdin, _stdout, rejected_curl_stderr, rejected_curl_wait_thread = Open3.popen3("curl #{HOST}:#{@tcp_port}")

    assert nil != Process.getpgid(@server.pid) # ensure server is still running
    assert nil != Process.getpgid(rejected_curl_wait_thread[:pid]) # ensure first curl invokation still in progress

    curl_wait_thread.join
    rejected_curl_wait_thread.join

    assert_match(/Slept 10/, curl_stdout.read)
    assert_match(/Connection refused/, rejected_curl_stderr.read)

    Process.wait(@server.pid)
    @server.close unless @server.closed?
    @server = nil # prevent `#teardown` from killing already killed server
  end
end
