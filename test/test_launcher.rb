require_relative "helper"
require_relative "helpers/tmp_path"

require "puma/configuration"
require 'puma/events'

class TestLauncher < Minitest::Test
  include TmpPath

  def test_files_to_require_after_prune_is_correctly_built_for_no_extra_deps
    skip_on :no_bundler

    dirs = launcher.send(:files_to_require_after_prune)

    assert_equal(2, dirs.length)
    assert_match(%r{puma/lib$}, dirs[0]) # lib dir
    assert_match(%r{puma-#{Puma::Const::PUMA_VERSION}$}, dirs[1]) # native extension dir
    refute_match(%r{gems/rdoc-[\d.]+/lib$}, dirs[2])
  end

  def test_files_to_require_after_prune_is_correctly_built_with_extra_deps
    skip_on :no_bundler
    conf = Puma::Configuration.new do |c|
      c.extra_runtime_dependencies ['rdoc']
    end

    dirs = launcher(conf).send(:files_to_require_after_prune)

    assert_equal(3, dirs.length)
    assert_match(%r{puma/lib$}, dirs[0]) # lib dir
    assert_match(%r{puma-#{Puma::Const::PUMA_VERSION}$}, dirs[1]) # native extension dir
    assert_match(%r{gems/rdoc-[\d.]+/lib$}, dirs[2]) # rdoc dir
  end

  def test_extra_runtime_deps_directories_is_empty_for_no_config
    assert_equal([], launcher.send(:extra_runtime_deps_directories))
  end

  def test_extra_runtime_deps_directories_is_correctly_built
    skip_on :no_bundler
    conf = Puma::Configuration.new do |c|
      c.extra_runtime_dependencies ['rdoc']
    end
    dep_dirs = launcher(conf).send(:extra_runtime_deps_directories)

    assert_equal(1, dep_dirs.length)
    assert_match(%r{gems/rdoc-[\d.]+/lib$}, dep_dirs.first)
  end

  def test_puma_wild_location_is_an_absolute_path
    skip_on :no_bundler
    puma_wild_location = launcher.send(:puma_wild_location)

    assert_match(%r{bin/puma-wild$}, puma_wild_location)
    # assert no "/../" in path
    refute_match(%r{/\.\./}, puma_wild_location)
  end

  def test_prints_thread_traces
    launcher.thread_status do |name, _backtrace|
      assert_match "Thread: TID", name
    end
  end

  def test_pid_file
    pid_path = tmp_path('.pid')

    conf = Puma::Configuration.new do |c|
      c.pidfile pid_path
    end

    launcher(conf).write_state

    assert_equal File.read(pid_path).strip.to_i, Process.pid

    File.unlink pid_path
  end

  def test_state_permission_0640
    state_path = tmp_path('.state')
    state_permission = 0640

    conf = Puma::Configuration.new do |c|
      c.state_path state_path
      c.state_permission state_permission
    end

    launcher(conf).write_state

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

    launcher(conf).write_state

    assert File.exist?(state_path)
  ensure
    File.unlink state_path
  end

  def test_no_state_permission
    state_path = tmp_path('.state')

    conf = Puma::Configuration.new do |c|
      c.state_path state_path
    end

    launcher(conf).write_state

    assert File.exist?(state_path)
  ensure
    File.unlink state_path
  end

  def test_puma_stats
    conf = Puma::Configuration.new do |c|
      c.app -> {[200, {}, ['']]}
      c.clear_binds!
    end
    launcher = launcher(conf)
    launcher.events.on_booted {
      sleep 1.1 unless Puma.mri?
      launcher.stop
    }
    launcher.run
    sleep 1 unless Puma.mri?
    Puma::Server::STAT_METHODS.each do |stat|
      assert_includes Puma.stats_hash, stat
    end
  end

  def test_puma_stats_clustered
    skip NO_FORK_MSG unless HAS_FORK

    conf = Puma::Configuration.new do |c|
      c.app -> {[200, {}, ['']]}
      c.workers 1
      c.clear_binds!
    end
    launcher = launcher(conf)
    Thread.new do
      sleep Puma::Const::WORKER_CHECK_INTERVAL + 1
      status = Puma.stats_hash[:worker_status].first[:last_status]
      Puma::Server::STAT_METHODS.each do |stat|
        assert_includes status, stat
      end
      launcher.stop
    end
    launcher.run
  end

  def test_log_config_enabled
    ENV['PUMA_LOG_CONFIG'] = "1"

    assert_match(/Configuration:/, launcher.events.stdout.string)

    launcher.config.final_options.each do |config_key, _value|
      assert_match(/#{config_key}/, launcher.events.stdout.string)
    end

    ENV.delete('PUMA_LOG_CONFIG')
  end

  def test_log_config_disabled
    refute_match(/Configuration:/, launcher.events.stdout.string)
  end

  private

  def events
    @events ||= Puma::Events.strings
  end

  def launcher(config = Puma::Configuration.new, evts = events)
    @launcher ||= Puma::Launcher.new(config, events: evts)
  end
end
