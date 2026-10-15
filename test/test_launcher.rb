# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/tmp_path"

require "puma/binder"
require "puma/configuration"
require 'puma/log_writer'
require "puma/runner"

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

  # The kernel ignores default-action signals sent to PID 1 (containers)
  def test_raise_sigterm_as_pid_1_exits_143
    runner = Puma::Runner.new(create_launcher)

    error = Process.stub(:pid, 1) do
      assert_raises(SystemExit) { runner.raise_sigterm }
    end
    assert_equal 143, error.status
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

    port = UniquePort.call
    ctl_url = "tcp://127.0.0.1:#{port}"
    ctl_socket = Addrinfo.tcp("127.0.0.1", port).listen
    ctl_socket.autoclose = false
    conf = Puma::Configuration.new do |c|
      c.app ->(_env) { [200, {}, ['ok']] }
      c.activate_control_app ctl_url, auth_token: 'none'
      c.bind_to_activated_sockets
    end
    log_writer = Puma::LogWriter.strings
    env = { 'LISTEN_FDS' => '1', 'LISTEN_PID' => Process.pid.to_s }

    binder_new = Puma::Binder.method(:new)
    activated_binder = ->(*args) do
      binder_new.call(*args).tap { |b| b.define_singleton_method(:socket_activation_fd) { |_| ctl_socket.fileno } }
    end
    launcher = Puma::Binder.stub(:new, activated_binder) { create_launcher(conf, log_writer, env: env) }
    launcher.binder.parse conf.options[:binds]
    runner = Puma::Single.new(launcher)
    runner.start_control

    client = TCPSocket.new "127.0.0.1", port
    client.write "GET /stats HTTP/1.0\r\n\r\n"

    assert_match(/\AHTTP\/1\.0 200 OK/, client.read)
    assert_includes log_writer.stdout.string, "* Activated #{ctl_url}"
    refute_includes log_writer.stdout.string, "Closing unused activated socket"
  ensure
    client&.close
    runner&.stop_control
    launcher&.binder&.close_listeners
  end

  private

  def create_launcher(config = Puma::Configuration.new, lw = Puma::LogWriter.strings, **kw)
    config.configure do |c|
      c.bind "tcp://127.0.0.1:#{UniquePort.call}"
    end
    Puma::Launcher.new(config, log_writer: lw, **kw)
  end
end
