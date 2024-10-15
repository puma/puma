# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/integration"

require "puma/plugin"

class TestSkipSystemd < TestIntegration

  def setup
    skip_unless :linux
    skip_unless :unix
    skip_unless_signal_exist? :TERM
    skip_if :jruby

    super
  end

  def teardown
    super unless skipped?
  end

  def test_systemd_plugin_not_loaded
    cli_server "test/rackup/hello.ru",
               env: { 'PUMA_SKIP_SYSTEMD' => 'true', 'NOTIFY_SOCKET' => '/tmp/doesntmatter' }, config: <<~CONFIG
      app do |_|
        [200, {}, [Puma::Plugins.instance_variable_get(:@plugins)['systemd'].to_s]]
      end
    CONFIG

    assert_empty send_http_read_resp_body

    stop_server
  end
end
