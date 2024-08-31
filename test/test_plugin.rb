require_relative "helper"
require_relative "helpers/integration"

class TestPlugin < TestIntegration
  def test_plugin
    skip "Skipped on Windows Ruby < 2.5.0, Ruby bug" if windows? && RUBY_VERSION < '2.5.0'
    @control_port = UniquePort.call

    Dir.mkdir("tmp") unless Dir.exist?("tmp")

    cli_server "--control-url tcp://#{HOST}:#{@control_port} --control-token #{TOKEN} test/rackup/hello.ru",
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
