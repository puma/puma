require_relative "helper"
require_relative "helpers/integration"

class TestPluginSystemdJruby < TestIntegration

  THREAD_LOG = TRUFFLE ? "{ 0/16 threads, 16 available, 0 backlog }" :
    "{ 0/5 threads, 5 available, 0 backlog }"

  def setup
    skip "Skipped because Systemd support is linux-only" if windows? || osx?
    skip_unless :unix
    skip_unless_signal_exist? :TERM
    skip_unless :jruby

    super

    ENV["NOTIFY_SOCKET"] = "/tmp/doesntmatter"
  end

  def test_systemd_skipped
    cli_server "test/rackup/hello.ru"

    assert_nil Puma::Plugins.instance_variable_get(:@plugins)["systemd"]

    stop_server
  end
end
