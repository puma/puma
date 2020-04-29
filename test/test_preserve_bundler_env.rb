require_relative "helper"
require_relative "helpers/integration"

class TestPreserveBundlerEnv < TestIntegration
#  parallelize_me!

  def setup
    skip NO_FORK_MSG unless HAS_FORK
    super
  end

  def teardown
    return if skipped?
    FileUtils.rm current_release_symlink, force: true
    super
  end

  # It does not wipe out BUNDLE_GEMFILE et al
  def test_usr2_restart_preserves_bundler_environment
    skip_unless_signal_exist? :USR2

    @tcp_port = 0
    env = {
      # Intentionally set this to something we wish to keep intact on restarts
      "BUNDLE_GEMFILE" => "Gemfile.bundle_env_preservation_test",
      # Don't allow our (rake test's) original env to interfere with the child process
      "BUNDLER_ORIG_BUNDLE_GEMFILE" => nil
    }
    # Must use `bundle exec puma` here, because otherwise Bundler may not be defined, which is required to trigger the bug
    cmd = "bundle exec puma -q -w 1 --prune-bundler -b tcp://#{HOST}:#{@tcp_port}"
    Dir.chdir(File.expand_path("bundle_preservation_test", __dir__)) do
      @server = IO.popen(env, cmd.split, "r", err: [:child, :out])
    end
    wait_for_server_to_boot
    @pid = @server.pid
    connection = connect
    initial_reply = read_body(connection)
    assert_match("Gemfile.bundle_env_preservation_test", initial_reply)
    restart_server connection
    new_reply = read_body(connection)
    assert_match("Gemfile.bundle_env_preservation_test", new_reply)
  end

  def test_phased_restart_preserves_unspecified_bundle_gemfile
    skip_unless_signal_exist? :USR1

    @tcp_port = 0
    env = {
      "BUNDLE_GEMFILE" => nil,
      "BUNDLER_ORIG_BUNDLE_GEMFILE" => nil
    }
    set_release_symlink File.expand_path("bundle_preservation_test/version1", __dir__)
    cmd = "bundle exec puma -q -w 1 --prune-bundler -b tcp://#{HOST}:#{@tcp_port}"
    Dir.chdir(current_release_symlink) do
      @server = IO.popen(env, cmd.split, "r", err: [:child, :out])
    end
    wait_for_server_to_boot
    @pid = @server.pid
    connection = connect

    # Bundler itself sets ENV['BUNDLE_GEMFILE'] to the Gemfile it finds if ENV['BUNDLE_GEMFILE'] was unspecified
    initial_reply = read_body(connection)
    expected_gemfile = File.expand_path("bundle_preservation_test/version1/Gemfile", __dir__).inspect
    assert_equal(expected_gemfile, initial_reply)

    set_release_symlink File.expand_path("bundle_preservation_test/version2", __dir__)
    start_phased_restart

    connection = connect
    connection.write "GET / HTTP/1.1\r\n\r\n"
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

    true while @server.gets !~ /booted, phase: 1/
  end
end
