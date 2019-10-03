require_relative "helper"
require_relative "helpers/integration"

class TestPlugin < TestIntegration
  include WaitForServerLogs

  def test_plugin
    skip "Skipped on Windows Ruby < 2.5.0, Ruby bug" if windows? && RUBY_VERSION < '2.5.0'
    @tcp_bind = UniquePort.call

    Dir.mkdir("tmp") unless Dir.exist?("tmp")

    cli_server "-C test/config/plugin1.rb test/rackup/hello.ru"
    File.open('tmp/restart.txt', mode: 'wb') { |f| f.puts "Restart #{Time.now}" }

    true while (l = @server.gets) !~ /Restarting\.\.\./
    assert_match(/Restarting\.\.\./, l)

    true while (l = @server.gets) !~ /Ctrl-C/
    assert_match(/Ctrl-C/, l)
  end
end
