# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/integration"

class TestPreserveBundlerEnv < TestIntegration
  def setup
    skip_unless :fork
    super
  end

  def teardown
    return if skipped?
    FileUtils.rm current_release_symlink, force: true
    super
  end

  # It does not wipe out BUNDLE_GEMFILE et al
  def test_usr2_restart_preserves_bundler_environment
    env = {
      # Intentionally set this to something we wish to keep intact on restarts
      "BUNDLE_GEMFILE" => "Gemfile.bundle_env_preservation_test",
      # Don't allow our (rake test's) original env to interfere with the child process
      "BUNDLER_ORIG_BUNDLE_GEMFILE" => nil
    }
    # Must use `bundle exec puma` here, because otherwise Bundler may not be defined, which is required to trigger the bug
    cmd = "-w 2 --prune-bundler"
    replies = ['', '']

    Dir.chdir(File.expand_path("bundle_preservation_test", __dir__)) do
      replies = restart_server_and_listen cmd, env: env
    end
    match = "Gemfile.bundle_env_preservation_test"

    assert_match(match, replies[0])
    assert_match(match, replies[1])
  end

  def test_worker_forking_preserves_bundler_config_path
    @tcp_port = UniquePort.call
    env = {
      # Disable the .bundle/config file in the bundle_app_config_test directory
      "BUNDLE_APP_CONFIG" => "/dev/null",
      # Don't allow our (rake test's) original env to interfere with the child process
      "BUNDLE_GEMFILE" => nil,
      "BUNDLER_ORIG_BUNDLE_GEMFILE" => nil
    }
    cmd = "-q -w 1 --prune-bundler"
    Dir.chdir File.expand_path("bundle_app_config_test", __dir__) do
      cli_server cmd, env: env
    end

    reply = read_body(connect)
    assert_equal("Hello World", reply)
  end

  def test_phased_restart_preserves_unspecified_bundle_gemfile
    @tcp_port = UniquePort.call
    env = {
      "BUNDLE_GEMFILE" => nil,
      "BUNDLER_ORIG_BUNDLE_GEMFILE" => nil
    }
    set_release_symlink File.expand_path("bundle_preservation_test/version1", __dir__)
    cmd = "-q -w 1 --prune-bundler"
    Dir.chdir(current_release_symlink) do
      cli_server cmd, env: env
    end
    connection = connect

    # Bundler itself sets ENV['BUNDLE_GEMFILE'] to the Gemfile it finds if ENV['BUNDLE_GEMFILE'] was unspecified
    initial_reply = read_body(connection)
    expected_gemfile = File.expand_path("bundle_preservation_test/version1/Gemfile", __dir__).inspect
    assert_equal(expected_gemfile, initial_reply)

    set_release_symlink File.expand_path("bundle_preservation_test/version2", __dir__)
    start_phased_restart

    connection = connect
    new_reply = read_body(connection)
    expected_gemfile = File.expand_path("bundle_preservation_test/version2/Gemfile", __dir__).inspect
    assert_equal(expected_gemfile, new_reply)
  end

  private

  def current_release_symlink
    File.expand_path "bundle_preservation_test/current", __dir__
  end

  def set_release_symlink(target_dir)
    FileUtils.rm current_release_symlink, force: true
    FileUtils.symlink target_dir, current_release_symlink, force: true
  end

  def start_phased_restart
    Process.kill :USR1, @pid
    wait_for_server_to_match(/booted in [.0-9]+s, phase: 1/)
  end
end
