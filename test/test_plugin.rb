# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/integration"

class TestPlugin < TestIntegration
  def test_plugin
    Dir.mkdir("tmp") unless Dir.exist?("tmp")

    cli_server "#{set_pumactl_args} test/rackup/hello.ru",
      config: "plugin 'tmp_restart'"

    File.open('tmp/restart.txt', mode: 'wb') { |f| f.puts "Restart #{Time.now}" }

    assert wait_for_server_to_include('Restarting...')

    assert wait_for_server_to_boot

    cli_pumactl "stop"

    assert wait_for_server_to_include('Goodbye')

    @server.close
    @server = nil
  end
end
