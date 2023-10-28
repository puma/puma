# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/test_puma/server_spawn"

require "puma/plugin"

class TestPluginSystemdJruby < TestPuma::ServerSpawn

  THREAD_LOG = TRUFFLE ? "{ 0/16 threads, 16 available, 0 backlog }" :
    "{ 0/5 threads, 5 available, 0 backlog }"

  def setup
    skip_unless :linux
    skip_unless :unix
    skip_unless_signal_exist? :TERM
    skip_unless :jruby

    ENV["NOTIFY_SOCKET"] = "/tmp/doesntmatter"
  end

  def teardown
    super unless skipped?
  end

  def test_systemd_plugin_not_loaded
    server_spawn "test/rackup/hello.ru"

    assert_nil Puma::Plugins.instance_variable_get(:@plugins)["systemd"]

    stop_server
  end
end
