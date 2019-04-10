require_relative "helper"

require 'puma/control_cli'

class TestPumaControlCli < Minitest::Test
  def setup
    # use a pipe to get info across thread boundary
    @wait, @ready = IO.pipe
  end

  def wait_booted
    line = @wait.gets until line =~ /Listening on/
  end

  def teardown
    @wait.close
    @ready.close
  end

  def find_open_port
    server = TCPServer.new("127.0.0.1", 0)
    server.addr[1]
  ensure
    server.close
  end

  def test_config_file
    control_cli = Puma::ControlCLI.new ["--config-file", "test/config/state_file_testing_config.rb", "halt"]
    assert_equal "t3-pid", control_cli.instance_variable_get("@pidfile")
  end

  def test_control_url
    host = "127.0.0.1"
    port = find_open_port
    url = "tcp://#{host}:#{port}/"

    opts = [
      "--control-url", url,
      "--control-token", "ctrl",
      "--config-file", "test/config/app.rb",
    ]

    control_cli = Puma::ControlCLI.new (opts + ["start"]), @ready, @ready
    t = Thread.new do
      Thread.current.abort_on_exception = true
      control_cli.run
    end

    wait_booted

    s = TCPSocket.new host, 9292
    s << "GET / HTTP/1.0\r\n\r\n"
    body = s.read
    assert_match "200 OK", body
    assert_match "embedded app", body

    shutdown_cmd = Puma::ControlCLI.new(opts + ["halt"])
    shutdown_cmd.run

    # TODO: assert something about the stop command

    t.join
  end
end
