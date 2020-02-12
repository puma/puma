require_relative "helper"
require_relative "helpers/integration"

class TestPlugin < TestIntegration
  def test_plugin
    skip "Skipped on Windows Ruby < 2.5.0, Ruby bug" if windows? && RUBY_VERSION < '2.5.0'
    @tcp_bind = UniquePort.call
    @tcp_ctrl = UniquePort.call

    Dir.mkdir("tmp") unless Dir.exist?("tmp")

    cli_server "-b tcp://#{HOST}:#{@tcp_bind} --control-url tcp://#{HOST}:#{@tcp_ctrl} --control-token #{TOKEN} -C test/config/plugin1.rb test/rackup/hello.ru"
    File.open('tmp/restart.txt', mode: 'wb') { |f| f.puts "Restart #{Time.now}" }

    true while (l = @server.gets) !~ /Restarting\.\.\./
    assert_match(/Restarting\.\.\./, l)

    true while (l = @server.gets) !~ /Ctrl-C/
    assert_match(/Ctrl-C/, l)

    out = StringIO.new

    cli_pumactl "-C tcp://#{HOST}:#{@tcp_ctrl} -T #{TOKEN} stop"
    true while (l = @server.gets) !~ /Goodbye/

    @server.close
    @server = nil
    out.close
  end

  private

  def cli_pumactl(argv)
    pumactl = IO.popen("#{BASE} bin/pumactl #{argv}", "r")
    @ios_to_close << pumactl
    Process.wait pumactl.pid
    pumactl
  end
end
