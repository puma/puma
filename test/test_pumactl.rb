require_relative "helper"
require_relative "helpers/config_file"
require_relative "helpers/ssl"

require 'pathname'
require 'puma/control_cli'

class TestPumaControlCli < TestConfigFileBase
  include SSLHelper

  def setup
    # use a pipe to get info across thread boundary
    @wait, @ready = IO.pipe
  end

  def wait_booted
    line = @wait.gets until line =~ /Use Ctrl-C to stop/
  end

  def teardown
    @wait.close
    @ready.close
  end

  def with_config_file(path_to_config, port)
    path = Pathname.new(path_to_config)
    Dir.mktmpdir do |tmp_dir|
      Dir.chdir(tmp_dir) do
        FileUtils.mkdir_p(path.dirname)
        File.open(path, "w") { |f| f << "port #{port}" }
        yield
      end
    end
  end

  def test_blank_command
    assert_system_exit_with_cli_output [], "Available commands: #{Puma::ControlCLI::CMD_PATH_SIG_MAP.keys.join(", ")}"
  end

  def test_invalid_command
    assert_system_exit_with_cli_output ['an-invalid-command'], 'Invalid command: an-invalid-command'
  end

  def test_config_file
    control_cli = Puma::ControlCLI.new ["--config-file", "test/config/state_file_testing_config.rb", "halt"]
    assert_equal "t3-pid", control_cli.instance_variable_get("@pidfile")
  end

  def test_rack_env_without_environment
    with_env("RACK_ENV" => "test") do
      control_cli = Puma::ControlCLI.new ["halt"]
      assert_equal "test", control_cli.instance_variable_get("@environment")
    end
  end

  def test_environment_without_rack_env
    with_env("RACK_ENV" => nil, 'RAILS_ENV' => nil) do
      control_cli = Puma::ControlCLI.new ["halt"]
      assert_nil control_cli.instance_variable_get("@environment")

      control_cli = Puma::ControlCLI.new ["-e", "test", "halt"]
      assert_equal "test", control_cli.instance_variable_get("@environment")
    end
  end

  def test_environment_with_rack_env
    with_env("RACK_ENV" => "production") do
      control_cli = Puma::ControlCLI.new ["halt"]
      assert_equal "production", control_cli.instance_variable_get("@environment")

      control_cli = Puma::ControlCLI.new ["-e", "test", "halt"]
      assert_equal "test", control_cli.instance_variable_get("@environment")
    end
  end

  def test_environment_specific_config_file_exist
    port = 6002
    puma_config_file = "config/puma.rb"
    production_config_file = "config/puma/production.rb"

    with_env("RACK_ENV" => nil) do
      with_config_file(puma_config_file, port) do
        control_cli = Puma::ControlCLI.new ["-e", "production", "halt"]
        assert_equal puma_config_file, control_cli.instance_variable_get("@config_file")
      end

      with_config_file(production_config_file, port) do
        control_cli = Puma::ControlCLI.new ["-e", "production", "halt"]
        assert_equal production_config_file, control_cli.instance_variable_get("@config_file")
      end
    end
  end

  def test_default_config_file_exist
    port = 6001
    puma_config_file = "config/puma.rb"
    development_config_file = "config/puma/development.rb"

    with_env("RACK_ENV" => nil, 'RAILS_ENV' => nil) do
      with_config_file(puma_config_file, port) do
        control_cli = Puma::ControlCLI.new ["halt"]
        assert_equal puma_config_file, control_cli.instance_variable_get("@config_file")
      end

      with_config_file(development_config_file, port) do
        control_cli = Puma::ControlCLI.new ["halt"]
        assert_equal development_config_file, control_cli.instance_variable_get("@config_file")
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
    port = UniquePort.call
    url = "tcp://#{host}:#{port}/"

    opts = [
      "--control-url", url,
      "--control-token", "ctrl",
      "--config-file", "test/config/app.rb",
    ]

    control_cli = Puma::ControlCLI.new (opts + ["start"]), @ready, @ready
    t = Thread.new do
      control_cli.run
    end

    wait_booted

    s = TCPSocket.new host, 9292
    s << "GET / HTTP/1.0\r\n\r\n"
    body = s.read
    assert_match "200 OK", body
    assert_match "embedded app", body

    assert_command_cli_output opts + ["status"], "Puma is started"
    assert_command_cli_output opts + ["stop"], "Command stop sent success"

    assert_kind_of Thread, t.join, "server didn't stop"
  end

  def test_control_ssl
    skip 'No ssl support' unless ::Puma::HAS_SSL

    host = "127.0.0.1"
    port = UniquePort.call
    url = "ssl://#{host}:#{port}?#{ssl_query}"

    opts = [
      "--control-url", url,
      "--control-token", "ctrl",
      "--config-file", "test/config/app.rb",
    ]

    control_cli = Puma::ControlCLI.new (opts + ["start"]), @ready, @ready
    t = Thread.new do
      control_cli.run
    end

    wait_booted

    assert_command_cli_output opts + ["status"], "Puma is started"
    assert_command_cli_output opts + ["stop"], "Command stop sent success"

    assert_kind_of Thread, t.join, "server didn't stop"
  end

  private

  def assert_command_cli_output(options, expected_out)
    cmd = Puma::ControlCLI.new(options)
    out, _ = capture_subprocess_io do
      begin
        cmd.run
      rescue SystemExit
      end
    end
    assert_match expected_out, out
  end

  def assert_system_exit_with_cli_output(options, expected_out)
    out, _ = capture_subprocess_io do
      response = assert_raises(SystemExit) do
        Puma::ControlCLI.new(options).run
      end

      assert_equal(response.status, 1)
    end

    assert_match expected_out, out
  end
end
