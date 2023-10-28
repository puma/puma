# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/test_puma/server_spawn"

class TestPlugin < TestPuma::ServerSpawn
  def test_plugin
    skip "Skipped on Windows Ruby < 2.5.0, Ruby bug" if windows? && RUBY_VERSION < '2.5.0'
    set_control_type :tcp

    Dir.mkdir("tmp") unless Dir.exist?("tmp")

    server_spawn "test/rackup/hello.ru",
      config: "plugin 'tmp_restart'"

    File.write 'tmp/restart.txt', "Restart #{Time.now}", mode: 'wb'

    assert wait_for_server_to_include('Restarting...')

    assert wait_for_server_to_include('Ctrl-C')

    cli_pumactl "stop"

    assert wait_for_server_to_include('Goodbye')

  ensure
    @server = nil if ::Puma::IS_WINDOWS # see ServerSpawn#after_teardown
  end
end
