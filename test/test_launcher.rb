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
    state_path = tmp_path('.state')
    state_permission = 0640

    conf = Puma::Configuration.new do |c|
      c.state_path state_path
      c.state_permission state_permission
    end

    create_launcher(conf).write_state

    assert File.stat(state_path).mode.to_s(8)[-4..-1], state_permission
  ensure
    File.unlink state_path
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
    launcher.events.on_booted {
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

  def test_fire_on_stopped
    conf = Puma::Configuration.new do |c|
      c.app -> {[200, {}, ['']]}
    end

    is_stopped = nil

    launcher = create_launcher(conf)
    launcher.events.on_booted {
      sleep 1.1 unless Puma.mri?
      launcher.stop
    }
    launcher.events.on_stopped { is_stopped = true }

    launcher.run
    sleep 0.2 unless Puma.mri?
    assert is_stopped, "on_stopped not called"
  end

  private

  def create_launcher(config = Puma::Configuration.new, lw = Puma::LogWriter.strings, **kw)
    config.configure do |c|
      c.bind "tcp://127.0.0.1:#{UniquePort.call}"
    end
    Puma::Launcher.new(config, log_writer: lw, **kw)
  end
end
