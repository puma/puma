# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/tmp_path"

require "puma/configuration"
require 'puma/log_writer'

# Do not add any tests creating workers to this, as Cluster may call `Process.waitall`,
# which may cause issues in the test process.

# Intermittent failures & errors when run parallel in GHA, local use may run fine.
class TestLauncher < PumaTest
  include TmpPath

  def test_prints_thread_traces
    create_launcher.thread_status do |name, _backtrace|
      assert_match "Thread: TID", name
    end
  end

  def test_pid_file
    pid_path = tmp_path('.pid')

    conf = Puma::Configuration.new do |c|
      c.pidfile pid_path
    end

    create_launcher(conf).write_state

    assert_equal File.read(pid_path).strip.to_i, Process.pid
  ensure
    File.unlink pid_path
  end

  def test_state_permission_0640
    state_path = nil
    skip_if :windows # only 0644 ?

    state_path = tmp_path('.state')
    state_permission = 0640

    conf = Puma::Configuration.new do |c|
      c.state_path state_path
      c.state_permission state_permission
    end

    create_launcher(conf).write_state

    assert_equal state_permission.to_s(8), File.stat(state_path).mode.to_s(8)[-3..-1]
  ensure
    File.unlink(state_path) if state_path
  end

  def test_state_permission_nil
    state_path = tmp_path('.state')

    conf = Puma::Configuration.new do |c|
      c.state_path state_path
      c.state_permission nil
    end

    create_launcher(conf).write_state

    assert File.exist?(state_path)
  ensure
    File.unlink state_path
  end

  def test_no_state_permission
    state_path = tmp_path('.state')

    conf = Puma::Configuration.new do |c|
      c.state_path state_path
    end

    create_launcher(conf).write_state

    assert File.exist?(state_path)
  ensure
    File.unlink state_path
  end

  def test_puma_stats
    conf = Puma::Configuration.new do |c|
      c.app -> {[200, {}, ['']]}
    end
    launcher = create_launcher(conf)
    launcher.events.after_booted {
      sleep 1.1 unless Puma.mri?
      launcher.stop
    }
    launcher.stats # Ensure `stats` method return without errors before run
    launcher.run
    sleep 1 unless Puma.mri?
    Puma::Server::STAT_METHODS.each do |stat|
      assert_includes launcher.stats, stat
    end
  end

  def test_log_config_enabled
    env = {'PUMA_LOG_CONFIG' => '1'}

    launcher = create_launcher env: env

    log = launcher.log_writer.stdout.string

    # the below confirms an exact match, allowing for line order differences
    launcher.config.final_options.each do |config_key, value|
      line = "- #{config_key}: #{value}\n"
      assert_includes log, line
      log.sub! line, ''
    end
    assert_equal 'Configuration:', log.strip
  end

  def test_log_config_disabled
    refute_match(/Configuration:/, create_launcher.log_writer.stdout.string)
  end

  def test_fire_after_stopped
    conf = Puma::Configuration.new do |c|
      c.app -> {[200, {}, ['']]}
    end

    is_stopped = nil

    launcher = create_launcher(conf)
    launcher.events.after_booted {
      sleep 1.1 unless Puma.mri?
      launcher.stop
    }
    launcher.events.after_stopped { is_stopped = true }

    launcher.run
    sleep 0.2 unless Puma.mri?
    assert is_stopped, "after_stopped not called"
  end

  def test_after_stopped_fires_after_requests_drain
    events = []
    runner = Object.new
    runner.define_singleton_method(:stop_blocked) { events << :requests_drained }
    launcher = create_launcher
    launcher.instance_variable_set(:@runner, runner)
    launcher.events.after_stopped { events << :after_stopped }

    launcher.send(:do_graceful_stop)

    assert_equal [:requests_drained, :after_stopped], events
  end

  def test_control_server_uses_activated_socket
    skip_unless :unix

    ctl_path = tmp_path('.sock')
    main_path = tmp_path('.sock')
    ctl_unix_server = UNIXServer.new ctl_path
    # Same type puma registers for a systemd activated socket
    ctl_server = TCPServer.for_fd ctl_unix_server.fileno
    ctl_unix_server.autoclose = false

    conf = Puma::Configuration.new do |c|
      c.app ->(_env) { [200, {}, ['ok']] }
      c.bind "unix://#{main_path}"
      c.activate_control_app "unix://#{ctl_path}", auth_token: 'none'
      c.log_requests false
    end

    launcher = create_launcher(conf)
    launcher.binder.activated_sockets[[:unix, ctl_path]] = ctl_server

    # Binding the app listeners must not close (or unlink) the socket that was
    # activated for the control server.
    launcher.binder.parse conf.options[:binds]
    refute ctl_server.closed?, "socket activated for the control URL was closed"
    assert File.exist?(ctl_path), "socket activated for the control URL was unlinked"
    assert_equal [[:unix, ctl_path]], launcher.binder.activated_sockets.keys

    runner = Puma::Single.new(launcher)
    begin
      runner.start_control
      assert_empty launcher.binder.activated_sockets

      # The control server must be serving on the very socket that was handed over.
      client = UNIXSocket.new ctl_path
      client.write "GET /stats HTTP/1.0\r\n\r\n"
      assert_match(/\AHTTP\/1\.0 200 OK/, client.read)
    ensure
      client&.close
      ctl_unix_server.close
      runner.stop_control
      launcher.binder.close_listeners
    end
  end

  private

  def create_launcher(config = Puma::Configuration.new, lw = Puma::LogWriter.strings, **kw)
    config.configure do |c|
      c.bind "tcp://127.0.0.1:#{UniquePort.call}"
    end
    Puma::Launcher.new(config, log_writer: lw, **kw)
  end
end
