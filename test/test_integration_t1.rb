require_relative "helper"
require_relative "helpers/integration"

class TestIntegrationSingle < TestIntegration
  parallelize_me!

  def test_write_to_log
    suppress_output = '> /dev/null 2>&1'
    cli_server "-C test/shell/t1_conf.rb test/rackup/hello.ru"

    sleep 1 until system "curl http://localhost:#{@tcp_port}/ #{suppress_output}"

    stop_server

    sleep 1

    log = File.read("t1-stdout")

    File.unlink "t1-stdout" if File.file? "t1-stdout"
    File.unlink "t1-pid" if File.file? "t1-pid"

    assert_match(%r!GET / HTTP/1\.1!, log)
  end
end
