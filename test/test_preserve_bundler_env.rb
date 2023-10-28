# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/test_puma/server_spawn"

class TestPreserveBundlerEnv < TestPuma::ServerSpawn
  def setup
    skip_unless :fork
  end

  def teardown
    return if skipped?
    FileUtils.rm current_release_symlink, force: true
  end

  # It does not wipe out BUNDLE_GEMFILE et al
  def test_usr2_restart_preserves_bundler_environment
    skip_unless_signal_exist? :USR2

    env = {
      # Intentionally set this to something we wish to keep intact on restarts
      "BUNDLE_GEMFILE" => "Gemfile.bundle_env_preservation_test",
      # Don't allow our (rake test's) original env to interfere with the child process
      "BUNDLER_ORIG_BUNDLE_GEMFILE" => nil
    }
    Dir.chdir(File.expand_path("bundle_preservation_test", __dir__)) do
      server_spawn "-q -w1 -t1:5 --prune-bundler", env: env
    end

    socket = send_http
    assert_includes socket.read_body, "Gemfile.bundle_env_preservation_test"

    restart_server socket

    assert_includes socket.read_body, "Gemfile.bundle_env_preservation_test"
  end

  def test_worker_forking_preserves_bundler_config_path
    skip_unless_signal_exist? :TERM

    env = {
      # Disable the .bundle/config file in the bundle_app_config_test directory
      "BUNDLE_APP_CONFIG" => "/dev/null",
      # Don't allow our (rake test's) original env to interfere with the child process
      "BUNDLE_GEMFILE" => nil,
      "BUNDLER_ORIG_BUNDLE_GEMFILE" => nil
    }
    Dir.chdir File.expand_path("bundle_app_config_test", __dir__) do
      server_spawn "-q -w1 -t1:5 --prune-bundler", env: env
    end

    assert_equal "Hello World", send_http_read_resp_body
  end

  def test_phased_restart_preserves_unspecified_bundle_gemfile
    skip_unless_signal_exist? :USR1

    env = {
      "BUNDLE_GEMFILE" => nil,
      "BUNDLER_ORIG_BUNDLE_GEMFILE" => nil
    }
    set_release_symlink File.expand_path("bundle_preservation_test/version1", __dir__)

    Dir.chdir(current_release_symlink) do
      server_spawn "-q -w1 -t1:5 --prune-bundler", env: env
    end

    # Bundler itself sets ENV['BUNDLE_GEMFILE'] to the Gemfile it finds if ENV['BUNDLE_GEMFILE'] was unspecified
    expected_gemfile = File.expand_path("bundle_preservation_test/version1/Gemfile", __dir__).inspect
    assert_equal(expected_gemfile, send_http_read_resp_body)

    set_release_symlink File.expand_path("bundle_preservation_test/version2", __dir__)
    start_phased_restart

    expected_gemfile = File.expand_path("bundle_preservation_test/version2/Gemfile", __dir__).inspect
    assert_equal(expected_gemfile, send_http_read_resp_body)
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
