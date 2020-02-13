require_relative "helper"
require_relative "helpers/integration"

class TestPreserveBundlerEnv < TestIntegration
  def setup
    skip NO_FORK_MSG unless HAS_FORK
    super
  end

  # It does not wipe out BUNDLE_GEMFILE et al
  def test_usr2_restart_preserves_bundler_environment
    @tcp_port = UniquePort.call
    env = {
      # Intentionally set this to something we wish to keep intact on restarts
      "BUNDLE_GEMFILE" => "Gemfile.bundle_env_preservation_test",
      # Don't allow our (rake test's) original env to interfere with the child process
      "BUNDLER_ORIG_BUNDLE_GEMFILE" => nil
    }
    # Must use `bundle exec puma` here, because otherwise Bundler may not be defined, which is required to trigger the bug
    cmd = "bundle exec puma -q -w 1 --prune-bundler -b tcp://#{HOST}:#{@tcp_port}"
    Dir.chdir(File.expand_path("bundle_preservation_test", __dir__)) do
      @server = IO.popen(env, cmd.split, "r")
    end
    wait_for_server_to_boot(log: true)
    @pid = @server.pid
    connection = connect
    initial_reply = read_body(connection)
    assert_match("Gemfile.bundle_env_preservation_test", initial_reply)
    restart_server connection, log: true
    new_reply = read_body(connection)
    assert_match("Gemfile.bundle_env_preservation_test", new_reply)
  end
end
