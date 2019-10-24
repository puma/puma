require_relative "helper"
require_relative "helpers/integration"

class TestIntegrationSingle < TestIntegration
  parallelize_me! unless Puma.jruby?

  def teardown
    return if skipped?
    super
  end

  def test_term_exit_code
    skip_unless_signal_exist? :TERM
    skip_on :jruby # JVM does not return correct exit code for TERM
    setup_puma bind: :tcp, ctrl: :pid

    cli_server "test/rackup/hello.ru"
    run_pumactl 'stop'

    begin
      _, status = Process.wait2 @pid
      assert_equal 15, status
    rescue Errno::ECHILD
    end
  end

  def test_term_suppress
    skip_unless_signal_exist? :TERM
    setup_puma bind: :tcp, ctrl: :pid

    cli_server "-C test/config/suppress_exception.rb test/rackup/hello.ru"
    run_pumactl 'stop'

    begin
      _, status = Process.wait2 @pid
      assert_equal 0, status
    rescue Errno::ECHILD
    end
  end

  def test_stop_closes_listeners_tcp_sgnl
    skip_unless_signal_exist? :TERM
    setup_puma bind: :tcp, ctrl: :pid
    stop_closes_listeners
  end

  def test_stop_closes_listeners_tcp_sock
    setup_puma bind: :tcp, ctrl: :tcp
    stop_closes_listeners
  end

  def test_int_refuse
    skip_unless_signal_exist? :INT
    setup_puma bind: :tcp, ctrl: :tcp

    cli_server 'test/rackup/hello.ru'
    begin
      sock = connect ''
      sock.close
    rescue => ex
      fail("Port didn't open properly: #{ex.message}")
    end

    Process.kill :INT, @pid
    Process.wait @pid

    assert_raises(Errno::ECONNREFUSED) { connect '' }
  end

  def test_thread_status_sgnl
    skip_unless_signal_exist? :INFO
    setup_puma bind: :tcp, ctrl: :pid

    cli_server 'test/rackup/hello.ru'

    Process.kill :INFO, @pid
    assert_io 'Thread: TID'
  end
end

# restart sets ENV variables, so these can't run parallel
# note: not phased-restart
class TestIntegrationSingleSerial < TestIntegration

  def teardown
    return if skipped?
    super
  end

  # It does not share environments between multiple generations, which would break Dotenv
  def test_restart_restores_environment_sgnl
    # jruby has a bug where setting `nil` into the ENV or `delete` do not change the
    # next workers ENV
    skip_on :jruby
    skip_unless_signal_exist? :USR2

    setup_puma bind: :tcp, ctrl: :pid
    pre, post = restart_server_and_listen "-q test/rackup/hello-env.ru"
    assert_includes pre , 'Hello RAND'
    assert_includes post, 'Hello RAND'
    refute_equal pre, post
  end

  def test_restart_sgnl
    skip_unless_signal_exist? :USR2
    setup_puma bind: :tcp, ctrl: :pid
    pre, post = restart_server_and_listen "-q test/rackup/hello.ru"
    assert_equal 'Hello World', pre
    assert_equal 'Hello World', post
  end

  def test_restart_sock
    setup_puma bind: :tcp, ctrl: :tcp
    pre, post = restart_server_and_listen "-q test/rackup/hello.ru"
    assert_equal 'Hello World', pre
    assert_equal 'Hello World', post
  end
end
