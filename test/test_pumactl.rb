require_relative "helper"
require_relative "helpers/config_file"

require 'puma/control_cli'
require 'pathname'

class TestPumaControlCli < TestConfigFileBase
  include WaitForServerLogs

  def setup
    # use a pipe to get info across thread boundary
    @wait, @ready = IO.pipe
  end

  def teardown
    @ready.close unless @ready.nil? || @ready.closed?
    @wait.close  unless @wait.nil?  || @wait.closed?
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

  def test_config_file
    control_cli = Puma::ControlCLI.new ['--config-file', 'test/config/state_file_testing_config.rb', 'halt']
    assert_equal "t3-pid", control_cli.instance_variable_get('@pidfile')
  end

  def test_rack_env_without_environment
    with_env("RACK_ENV" => "test") do
      control_cli = Puma::ControlCLI.new ["halt"]
      assert_equal "test", control_cli.instance_variable_get("@environment")
    end
  end

  def test_environment_without_rack_env
    with_env("RACK_ENV" => nil) do
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

    with_env("RACK_ENV" => nil) do
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
      '--config-file', 'test/config/control_no_token.rb',
      'start'
    ]

    control_cli = Puma::ControlCLI.new opts, @ready, @ready
    assert_equal 'none', control_cli.instance_variable_get('@control_auth_token')
  end

  def test_control_url_and_status_halt
    host = '127.0.0.1'
    port = UniquePort.call
    url = "tcp://#{host}:#{port}/"

    opts = [
      '--control-url'  , url,
      '--control-token', 'ctrl'
    ]

    control_cli = Puma::ControlCLI.new(opts + ['--config-file', 'test/config/app.rb', 'start'], @ready, @ready)
    t = Thread.new do
      control_cli.run
    end

    assert_io 'Ctrl-C', io: @wait

    s = TCPSocket.new host, 9292
    s << "GET / HTTP/1.0\r\n\r\n"
    body = s.read
    assert_match "200 OK", body
    assert_match "embedded app", body
    s.close

    Puma::ControlCLI.new(opts + ['status'], @ready, @ready).run
    assert_io 'Puma is started', io: @wait

    Puma::ControlCLI.new(opts + ['halt'], @ready, @ready).run
    assert_io 'Command halt sent success', io: @wait
    assert_io 'Stopping immediately', io: @wait

    assert_kind_of Thread, t.join, "server didn't halt"
  ensure
    s.close unless s.nil? || s.closed?
  end

  def test_control_url_and_status_stop
    host = '127.0.0.1'
    port = UniquePort.call
    url = "tcp://#{host}:#{port}/"

    opts = [
      '--control-url'  , url,
      '--control-token', 'ctrl'
    ]

    control_cli = Puma::ControlCLI.new(opts + ['--config-file', 'test/config/app.rb', 'start'], @ready, @ready)
    t = Thread.new do
      control_cli.run
    end

    assert_io 'Ctrl-C', io: @wait

    s = TCPSocket.new host, 9292
    s << "GET / HTTP/1.0\r\n\r\n"
    body = s.read
    assert_match "200 OK", body
    assert_match "embedded app", body
    s.close

    Puma::ControlCLI.new(opts + ['status'], @ready, @ready).run
    assert_io 'Puma is started', io: @wait

    Puma::ControlCLI.new(opts + ['stop'], @ready, @ready).run
    assert_io 'Command stop sent success', io: @wait
    assert_io 'Goodbye', io: @wait

    assert_kind_of Thread, t.join, "server didn't stop"
  ensure
    s.close unless s.nil? || s.closed?
  end
end
