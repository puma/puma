require_relative "helper"
require_relative "helpers/integration"

class TestPlugin < TestIntegration
  def test_plugin_sock
    setup_puma bind: :tcp, ctrl: :tcp

    cli_server "-C test/config/plugin1.rb test/rackup/hello.ru"

    File.open('tmp/restart.txt', mode: 'wb') { |f| f.puts "Restart #{Time.now}" }

    assert_io 'Restarting...'
    assert_io 'Ctrl-C'
    @pid = File.read(@path_pid, mode: 'rb').strip.to_i

  ensure
    File.unlink('tmp/restart.txt') if File.exist? 'tmp/restart.txt'
  end
end
