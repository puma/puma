# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/ssl"

require 'pathname'
require 'puma/control_cli'

class TestPumaControlCli < PumaTest
  include SSLHelper

  def setup
    # use a pipe to get info across thread boundary
    @wait, @ready = IO.pipe
  end

  def wait_booted(log: nil)
    @server_log = +''
    begin
      sleep 0.01 until @wait.wait_readable(0.01)
      line = @wait.gets
      STDOUT.syswrite "#{line}\n" if log
      @server_log << line
    end until line&.include?('Use Ctrl-C to stop')
  end

  def teardown
    @wait.close
    @ready.close unless @ready.closed?
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
    assert_equal "t3-pid", control_cli.instance_variable_get(:@pidfile)
  ensure
    File.unlink "t3-pid" if File.file? "t3-pid"
  end

  def test_app_env_without_environment
    env = { 'APP_ENV' => 'test' }
    control_cli = Puma::ControlCLI.new ['halt'], env: env
    assert_equal 'test', control_cli.instance_variable_get(:@environment)
  end

  def test_rack_env_without_environment
    env = { "RACK_ENV" => "test" }
    control_cli = Puma::ControlCLI.new ["halt"], env: env
    assert_equal "test", control_cli.instance_variable_get(:@environment)
  end

  def test_app_env_precedence
    env = { 'APP_ENV' => nil, 'RACK_ENV' => nil, 'RAILS_ENV' => 'production' }
    control_cli = Puma::ControlCLI.new ['halt'], env: env
    assert_equal 'production', control_cli.instance_variable_get(:@environment)

    env = { 'APP_ENV' => nil, 'RACK_ENV' => 'test', 'RAILS_ENV' => 'production' }
    control_cli = Puma::ControlCLI.new ['halt'], env: env
    assert_equal 'test', control_cli.instance_variable_get(:@environment)

    env = { 'APP_ENV' => 'development', 'RACK_ENV' => 'test', 'RAILS_ENV' => 'production' }
    control_cli = Puma::ControlCLI.new ['halt'], env: env
    assert_equal 'development', control_cli.instance_variable_get(:@environment)

    control_cli = Puma::ControlCLI.new ['-e', 'test', 'halt'], env: env
    assert_equal 'test', control_cli.instance_variable_get(:@environment)
  end

  def test_environment_without_app_env
    env = { 'APP_ENV' => nil, 'RACK_ENV' => nil, 'RAILS_ENV' => nil }

    control_cli = Puma::ControlCLI.new ['halt'], env: env
    assert_nil control_cli.instance_variable_get(:@environment)

    control_cli = Puma::ControlCLI.new ['-e', 'test', 'halt'], env: env
    assert_equal 'test', control_cli.instance_variable_get(:@environment)
  end

  def test_environment_without_rack_env
    env = { "RACK_ENV" => nil, 'RAILS_ENV' => nil }

    control_cli = Puma::ControlCLI.new ["halt"], env: env
    assert_nil control_cli.instance_variable_get(:@environment)

    control_cli = Puma::ControlCLI.new ["-e", "test", "halt"]
    assert_equal "test", control_cli.instance_variable_get(:@environment)
  end

  def test_environment_with_rack_env
    env = { "RACK_ENV" => "production" }

    control_cli = Puma::ControlCLI.new ["halt"], env: env
    assert_equal "production", control_cli.instance_variable_get(:@environment)

    control_cli = Puma::ControlCLI.new ["-e", "test", "halt"], env: env
    assert_equal "test", control_cli.instance_variable_get(:@environment)
  end

  def test_environment_specific_config_file_exist
    port = UniquePort.call
    puma_config_file = "config/puma.rb"
    production_config_file = "config/puma/production.rb"

    env = { "RACK_ENV" => nil }

    with_config_file(puma_config_file, port) do
      control_cli = Puma::ControlCLI.new ["-e", "production", "halt"], env: env
      assert_equal puma_config_file, control_cli.instance_variable_get(:@config_file)
    end

    with_config_file(production_config_file, port) do
      control_cli = Puma::ControlCLI.new ["-e", "production", "halt"], env: env
      assert_equal production_config_file, control_cli.instance_variable_get(:@config_file)
    end
  end

  def test_default_config_file_exist
    port = UniquePort.call
    puma_config_file = "config/puma.rb"
    development_config_file = "config/puma/development.rb"

    env = { "RACK_ENV" => nil, 'RAILS_ENV' => nil }

    with_config_file(puma_config_file, port) do
      control_cli = Puma::ControlCLI.new ["halt"], env: env
      assert_equal puma_config_file, control_cli.instance_variable_get(:@config_file)
    end

    with_config_file(development_config_file, port) do
      control_cli = Puma::ControlCLI.new ["halt"], env: env
      assert_equal development_config_file, control_cli.instance_variable_get(:@config_file)
    end
  end

  def test_control_no_token
    opts = [
      "--config-file", "test/config/control_no_token.rb",
      "start"
    ]

    control_cli = Puma::ControlCLI.new opts, @ready, @ready
    assert_equal 'none', control_cli.instance_variable_get(:@control_auth_token)
  end

  def test_control_url_and_status
    host = "localhost"
    port = UniquePort.call
    url = "tcp://#{host}:#{port}/"

    opts = [
      "--control-url", url,
      "--control-token", "ctrl",
      "--config-file", "test/config/app.rb"
    ]

    control_cli = Puma::ControlCLI.new (opts + ["start"]), @ready, @ready
    t = Thread.new do
      control_cli.run
    end

    wait_booted # read server log

    bind_port = @server_log[/Listening on http:.+:(\d+)$/, 1].to_i
    s = TCPSocket.new host, bind_port
    s << "GET / HTTP/1.0\r\n\r\n"
    body = s.read
    assert_includes body, "200 OK"
    assert_includes body, "embedded app"

    assert_command_cli_output opts + ["status"], "Puma is started"
    assert_command_cli_output opts + ["stop"], "Command stop sent success"

    assert_kind_of Thread, t.join, "server didn't stop"
  end

  # This checks that a 'signal only' command is sent
  # they are defined by the `Puma::ControlCLI::NO_REQ_COMMANDS` array
  # test is skipped unless NO_REQ_COMMANDS is defined
  def test_control_url_with_signal_only_cmd
    skip_if :windows
    skip unless defined? Puma::ControlCLI::NO_REQ_COMMANDS
    host = "127.0.0.1"
    port = UniquePort.call
    url = "tcp://#{host}:#{port}/"

    opts = [
      "--control-url", url,
      "--control-token", "ctrl",
      "--config-file", "test/config/app.rb",
      "--pid", "1234"
    ]
    cmd = Puma::ControlCLI::NO_REQ_COMMANDS.first
    log = +''
    control_cli = Puma::ControlCLI.new (opts + [cmd]), @ready, @ready

    def control_cli.send_signal
      message "send_signal #{@command}\n"
    end
    def control_cli.send_request
      message "send_request #{@command}\n"
    end

    control_cli.run
    @ready.close

    log = @wait.read

    assert_includes log, "send_signal #{cmd}"
    refute_includes log, 'send_request'
  end

  def control_ssl_certificate(ip)
    require 'openssl'
    key = OpenSSL::PKey::RSA.generate(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = cert.issuer = OpenSSL::X509::Name.parse('/CN=localhost')
    cert.public_key = key.public_key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + 3600
    factory = OpenSSL::X509::ExtensionFactory.new
    factory.subject_certificate = factory.issuer_certificate = cert
    cert.add_extension factory.create_extension('subjectAltName', "IP:#{ip}")
    cert.add_extension factory.create_extension('basicConstraints', 'CA:FALSE', true)
    cert.sign(key, OpenSSL::Digest::SHA256.new)
    [key, cert]
  end

  def control_ssl(host)
    skip_unless :ssl
    ip = host&.start_with?('[') ? host[1..-2] : host
    port = UniquePort.call(ip)

    Dir.mktmpdir do |dir|
      key, cert = control_ssl_certificate(ip)
      cert_path = File.join(dir, 'cert.pem')
      File.write(cert_path, cert.to_pem)
      query = if Puma.jruby?
        keystore = File.join(dir, 'control.p12')
        File.binwrite(keystore, OpenSSL::PKCS12.create('password', 'puma', key, cert).to_der)
        "keystore=#{keystore}&keystore-pass=password&keystore-type=PKCS12"
      else
        key_path = File.join(dir, 'key.pem')
        File.write(key_path, key.to_pem)
        "key=#{key_path}&cert=#{cert_path}"
      end

      url = "ssl://#{host}:#{port}?#{query}"
      opts = [
        "--control-url", url,
        "--control-token", "ctrl",
        "--control-ca-file", cert_path,
        "--config-file", "test/config/app.rb"
      ]

      control_cli = Puma::ControlCLI.new (opts + ["start"]), @ready, @ready
      t = Thread.new { control_cli.run }

      wait_booted

      assert_command_cli_output opts + ["status"], "Puma is started"
      assert_command_cli_output opts + ["stop"], "Command stop sent success"

      assert_kind_of Thread, t.join, "server didn't stop"
    end
  end


  def test_control_ssl_ipv4
    skip_unless :ssl
    control_ssl '127.0.0.1'
  end

  def test_control_ssl_ipv6
    skip_unless :ssl
    control_ssl '[::1]'
  end

  def assert_control_ssl_rejected(cert_ip, trusted:)
    key, cert = control_ssl_certificate(cert_ip)
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.cert = cert
    ctx.key = key
    server = TCPServer.new('127.0.0.1', 0)
    thread = Thread.new do
      socket = OpenSSL::SSL::SSLSocket.new(server.accept, ctx)
      socket.sync_close = true
      socket.accept
      socket.gets
    rescue OpenSSL::SSL::SSLError, EOFError, Errno::ECONNRESET
      nil
    ensure
      socket&.sysclose
    end

    Dir.mktmpdir do |dir|
      cert_path = File.join(dir, 'cert.pem')
      File.write(cert_path, cert.to_pem)
      opts = ['--control-url', "ssl://127.0.0.1:#{server.addr[1]}", '--control-token', 'secret']
      opts.concat(['--control-ca-file', cert_path]) if trusted

      assert_raises(OpenSSL::SSL::SSLError) do
        Puma::ControlCLI.new(opts + ['stats'], @ready, @ready).send_request
      end
      assert_kind_of Thread, thread.join(5), 'control server did not finish'
      assert_nil thread.value
    end
  ensure
    thread&.kill&.join
    server&.close
  end

  def test_control_ssl_rejects_untrusted_certificate
    skip_unless :ssl
    assert_control_ssl_rejected('127.0.0.1', trusted: false)
  end

  def test_control_ssl_rejects_wrong_host
    skip_unless :ssl
    assert_control_ssl_rejected('127.0.0.2', trusted: true)
  end

  def test_control_aunix
    skip_unless :aunix

    url = "unix://@test_control_aunix.unix"

    opts = [
      "--control-url", url,
      "--control-token", "ctrl",
      "--config-file", "test/config/app.rb"
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

  def test_control_ipv6
    port = UniquePort.call '::1'
    url = "tcp://[::1]:#{port}"

    opts = [
      "--control-url", url,
      "--control-token", "ctrl",
      "--config-file", "test/config/app.rb"
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
    @rd, @wr = IO.pipe
    cmd = Puma::ControlCLI.new(options, @wr, @wr)
    begin
      cmd.run
    rescue SystemExit
    end
    @wr.close
    if String === expected_out
      assert_includes @rd.read, expected_out
    else
      assert_match expected_out, @rd.read
    end
  ensure
    @rd.close
  end

  def assert_system_exit_with_cli_output(options, expected_out)
    @rd, @wr = IO.pipe

    response = assert_raises(SystemExit) do
      Puma::ControlCLI.new(options, @wr, @wr).run
    end
    @wr.close

    assert_equal(response.status, 1)
    if String === expected_out
      assert_includes @rd.read, expected_out
    else
      assert_match expected_out, @rd.read
    end
  ensure
    @rd.close
  end
end
