require_relative "helper"
require_relative "helpers/integration"

class TestPreserveBundlerEnv < TestIntegration
  def setup
    skip NO_FORK_MSG unless HAS_FORK
    super
  end

  # It does not wipe out BUNDLE_GEMFILE et al
  def test_usr2_restart_preserves_bundler_environment
    skip_unless_signal_exist? :USR2

    @tcp_port = UniquePort.call
    gem_home = "/home/bundle_env_preservation_test"
    bundle_gemfile = "Gemfile.bundle_env_preservation_test"
    env = {
      "GEM_HOME" => gem_home,
      # Intentionally set this to something we wish to keep intact on restarts
      "BUNDLE_GEMFILE" => bundle_gemfile,
      # Don't allow our (rake test's) original env to interfere with the child process
      "BUNDLER_ORIG_BUNDLE_GEMFILE" => nil
    }
    # Must use `bundle exec puma` here, because otherwise Bundler may not be defined, which is required to trigger the bug
    cmd = "bundle exec puma -q -w 1 --prune-bundler -b tcp://#{HOST}:#{@tcp_port}"
    Dir.chdir(File.expand_path("bundle_preservation_test", __dir__)) do
      @server = IO.popen(env, cmd.split, "r")
    end
    wait_for_server_to_boot
    @pid = @server.pid
    connection = connect
    initial_reply = read_body(connection)
    refute_match(bundle_gemfile, initial_reply)
    assert_match(gem_home, initial_reply)
    restart_server connection
    new_reply = read_body(connection)
    refute_match(bundle_gemfile, new_reply)
    assert_match(gem_home, initial_reply)
  end
end
