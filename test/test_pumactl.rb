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

  def test_environment
    ENV.delete 'RACK_ENV' # remove from travis
    control_cli = Puma::ControlCLI.new ["halt"]
    assert_equal "development", control_cli.instance_variable_get("@environment")
    control_cli = Puma::ControlCLI.new ["-e", "test", "halt"]
    assert_equal "test", control_cli.instance_variable_get("@environment")
  end

  def test_config_file_exist
    ENV.delete 'RACK_ENV' # remove from travis
    port = 6001
    Dir.mktmpdir do |d|
      Dir.chdir(d) do
        FileUtils.mkdir("config")
        File.open("config/puma.rb", "w") { |f| f << "port #{port}" }
        control_cli = Puma::ControlCLI.new ["halt"]
        assert_equal "config/puma.rb",
          control_cli.instance_variable_get("@config_file")
      end
    end
    Dir.mktmpdir do |d|
      Dir.chdir(d) do
        FileUtils.mkdir_p("config/puma")
        File.open("config/puma/development.rb", "w") { |f| f << "port #{port}" }
        control_cli = Puma::ControlCLI.new ["halt"]
        assert_equal "config/puma/development.rb",
          control_cli.instance_variable_get("@config_file")
      end
    end
  end

  def test_control_no_token
    opts = [
      "--config-file", "test/config/control_no_token.rb",
      "start"
    ]

    control_cli = Puma::ControlCLI.new opts, @ready, @ready
    assert_equal 'none', control_cli.instance_variable_get("@control_auth_token")
  end

  def test_control_url_and_status
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

    status_cmd = Puma::ControlCLI.new(opts + ["status"])
    out, _ = capture_subprocess_io do
      status_cmd.run
    end
    assert_match "Puma is started\n", out

    shutdown_cmd = Puma::ControlCLI.new(opts + ["halt"])
    out, _ = capture_subprocess_io do
      shutdown_cmd.run
    end
    assert_match "Command halt sent success\n", out

    assert_kind_of Thread, t.join, "server didn't stop"
  end
end
