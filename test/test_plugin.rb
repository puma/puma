require_relative "helper"
require_relative "helpers/integration"

class TestPlugin < TestIntegration
  parallelize_me!

  def test_plugin
    skip "Skipped on Windows Ruby < 2.5.0, Ruby bug" if windows? && RUBY_VERSION < '2.5.0'

    Dir.mkdir("tmp") unless Dir.exist?("tmp")

    File.open('tmp/restart.txt', mode: 'wb') do |f|
      cli_server "-b tcp://#{HOST}:0 --control-url tcp://#{HOST}:0 --control-token #{TOKEN} -C test/config/plugin1.rb test/rackup/hello.ru"
      f.puts "Restart #{Time.now}"
    end
    true while (l = @server.gets) !~ /Restarting\.\.\./
    assert_match(/Restarting\.\.\./, l)

    wait_for_server_to_boot

    cli_pumactl "-C tcp://#{HOST}:#{@tcp_ctrl} -T #{TOKEN} stop"
    true while (l = @server.gets) !~ /Goodbye/

    @server.close
    @server = nil
  end

  private

  def cli_pumactl(argv)
    pumactl = IO.popen("#{BASE} bin/pumactl #{argv}", "r")
    @ios_to_close << pumactl
    Process.wait pumactl.pid
    pumactl
  end
end
