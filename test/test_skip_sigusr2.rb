# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/integration"

require "puma/plugin"

class TestSkipSigusr2 < TestIntegration

  def setup
    skip_unless_signal_exist? :TERM
    skip_unless_signal_exist? :USR2

    super
  end

  def teardown
    super unless skipped?
  end

  def test_sigusr2_handler_not_installed
    cli_server "test/rackup/hello.ru",
               env: { 'PUMA_SKIP_SIGUSR2' => 'true' }, config: <<~CONFIG
      app do |_|
        [200, {}, [Signal.trap('SIGUSR2', 'IGNORE').to_s]]
      end
    CONFIG

    assert_equal 'DEFAULT', read_body(connect)

    stop_server
  end
end
