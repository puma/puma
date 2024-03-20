require_relative "helper"
require_relative "helpers/integration"

class TestWorkerGemIndependence < TestIntegration
  def setup
    skip_unless :fork
    super
  end

  def teardown
    return if skipped?
    FileUtils.rm current_release_symlink, force: true
    super
  end

  def test_changing_nio4r_version_during_phased_restart
    change_gem_version_during_phased_restart old_app_dir: 'worker_gem_independence_test/old_nio4r',
                                             old_version: '2.6.0',
                                             new_app_dir: 'worker_gem_independence_test/new_nio4r',
                                             new_version: '2.6.1'
  end

  def test_changing_json_version_during_phased_restart
    change_gem_version_during_phased_restart old_app_dir: 'worker_gem_independence_test/old_json',
                                             old_version: '2.3.1',
                                             new_app_dir: 'worker_gem_independence_test/new_json',
                                             new_version: '2.3.0'
  end

  def test_changing_json_version_during_phased_restart_after_querying_stats_from_status_server
    @control_tcp_port = UniquePort.call
    server_opts = "--control-url tcp://#{HOST}:#{@control_tcp_port} --control-token #{TOKEN}"
    before_restart = ->() do
      cli_pumactl "stats"
    end

    change_gem_version_during_phased_restart server_opts: server_opts,
                                             before_restart: before_restart,
                                             old_app_dir: 'worker_gem_independence_test/old_json',
                                             old_version: '2.3.1',
                                             new_app_dir: 'worker_gem_independence_test/new_json',
                                             new_version: '2.3.0'
  end

  def test_changing_json_version_during_phased_restart_after_querying_gc_stats_from_status_server
    @control_tcp_port = UniquePort.call
    server_opts = "--control-url tcp://#{HOST}:#{@control_tcp_port} --control-token #{TOKEN}"
    before_restart = ->() do
      cli_pumactl "gc-stats"
    end

    change_gem_version_during_phased_restart server_opts: server_opts,
                                             before_restart: before_restart,
                                             old_app_dir: 'worker_gem_independence_test/old_json',
                                             old_version: '2.3.1',
                                             new_app_dir: 'worker_gem_independence_test/new_json',
                                             new_version: '2.3.0'
  end

  def test_changing_json_version_during_phased_restart_after_querying_thread_backtraces_from_status_server
    @control_tcp_port = UniquePort.call
    server_opts = "--control-url tcp://#{HOST}:#{@control_tcp_port} --control-token #{TOKEN}"
    before_restart = ->() do
      cli_pumactl "thread-backtraces"
    end

    change_gem_version_during_phased_restart server_opts: server_opts,
                                             before_restart: before_restart,
                                             old_app_dir: 'worker_gem_independence_test/old_json',
                                             old_version: '2.3.1',
                                             new_app_dir: 'worker_gem_independence_test/new_json',
                                             new_version: '2.3.0'
  end

  def test_changing_json_version_during_phased_restart_after_accessing_puma_stats_directly
    change_gem_version_during_phased_restart old_app_dir: 'worker_gem_independence_test/old_json_with_puma_stats_after_fork',
                                             old_version: '2.3.1',
                                             new_app_dir: 'worker_gem_independence_test/new_json_with_puma_stats_after_fork',
                                             new_version: '2.3.0'
  end

  private

  def change_gem_version_during_phased_restart(old_app_dir:,
                                               new_app_dir:,
                                               old_version:,
                                               new_version:,
                                               server_opts: '',
                                               before_restart: nil)
    skip_unless_signal_exist? :USR1

    set_release_symlink File.expand_path(old_app_dir, __dir__)

    Dir.chdir(current_release_symlink) do
      with_unbundled_env do
        silent_and_checked_system_command("bundle config --local path vendor/bundle")
        silent_and_checked_system_command("bundle install")
        cli_server "--prune-bundler -w 1 #{server_opts}"
      end
    end

    connection = connect
    initial_reply = read_body(connection)
    assert_equal old_version, initial_reply

    before_restart&.call

    set_release_symlink File.expand_path(new_app_dir, __dir__)
    Dir.chdir(current_release_symlink) do
      with_unbundled_env do
        silent_and_checked_system_command("bundle config --local path vendor/bundle")
        silent_and_checked_system_command("bundle install")
      end
    end
    start_phased_restart

    connection = connect
    new_reply = read_body(connection)
    assert_equal new_version, new_reply
  end

  def current_release_symlink
    File.expand_path "worker_gem_independence_test/current", __dir__
  end

  def set_release_symlink(target_dir)
    FileUtils.rm current_release_symlink, force: true
    FileUtils.symlink target_dir, current_release_symlink, force: true
  end

  def start_phased_restart
    Process.kill :USR1, @pid

    true while @server.gets !~ /booted in [.0-9]+s, phase: 1/
  end

  def with_unbundled_env
    bundler_ver = Gem::Version.new(Bundler::VERSION)
    if bundler_ver < Gem::Version.new('2.1.0')
      Bundler.with_clean_env { yield }
    else
      Bundler.with_unbundled_env { yield }
    end
  end
end
