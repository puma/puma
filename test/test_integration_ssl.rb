require_relative 'helper'
require_relative "helpers/integration"

# These tests are used to verify that Puma works with SSL sockets.  Only
# integration tests isolate the server from the test environment, so there
# should be a few SSL tests.
#
# For instance, since other tests make use of 'client' SSLSockets created by
# net/http, OpenSSL is loaded in the CI process.  By shelling out with IO.popen,
# the server process isn't affected by whatever is loaded in the CI process.

class TestIntegrationSSL < TestIntegration
  parallelize_me! if ::Puma.mri?

  require "net/http"
  require "openssl"

  def teardown
    @server.close unless @server.closed?
    @server = nil
    super
  end

  def bind_port
    @bind_port ||= UniquePort.call
  end

  def control_tcp_port
    @control_tcp_port ||= UniquePort.call
  end

  def with_server(config)
    config_file = Tempfile.new %w(config .rb)
    config_file.write config
    config_file.close
    config_file.path

    # start server
    cmd = "#{BASE} bin/puma -C #{config_file.path}"
    @server = IO.popen cmd, 'r'
    wait_for_server_to_boot
    @pid = @server.pid

    http = Net::HTTP.new HOST, bind_port
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    yield http

    # stop server
    sock = TCPSocket.new HOST, control_tcp_port
    @ios_to_close << sock
    sock.syswrite "GET /stop?token=#{TOKEN} HTTP/1.1\r\n\r\n"
    sock.read
    assert_match 'Goodbye!', @server.read
  end

  def test_ssl_run
    config = <<RUBY
if ::Puma.jruby?
  keystore =  '#{File.expand_path '../examples/puma/keystore.jks', __dir__}'
  keystore_pass = 'jruby_puma'

  ssl_bind '#{HOST}', '#{bind_port}', {
    keystore: keystore,
    keystore_pass:  keystore_pass,
    verify_mode: 'none'
  }
else
  key  = '#{File.expand_path '../examples/puma/puma_keypair.pem', __dir__}'
  cert = '#{File.expand_path '../examples/puma/cert_puma.pem', __dir__}'

  ssl_bind '#{HOST}', '#{bind_port}', {
    cert: cert,
    key:  key,
    verify_mode: 'none'
  }
end

activate_control_app 'tcp://#{HOST}:#{control_tcp_port}', { auth_token: '#{TOKEN}' }

app do |env|
  [200, {}, [env['rack.url_scheme']]]
end
RUBY
    with_server(config) do |http|
      body = nil
      http.start do
        req = Net::HTTP::Get.new '/', {}
        http.request(req) { |resp| body = resp.body }
      end
      assert_equal 'https', body
    end
  end

  def test_ssl_run_with_pem
    skip_if :jruby

    config = <<RUBY
  key_path  = '#{File.expand_path '../examples/puma/puma_keypair.pem', __dir__}'
  cert_path = '#{File.expand_path '../examples/puma/cert_puma.pem', __dir__}'

  ssl_bind '#{HOST}', '#{bind_port}', {
    cert_pem: File.read(cert_path),
    key_pem:  File.read(key_path),
    verify_mode: 'none'
  }

activate_control_app 'tcp://#{HOST}:#{control_tcp_port}', { auth_token: '#{TOKEN}' }

app do |env|
  [200, {}, [env['rack.url_scheme']]]
end
RUBY

    with_server(config) do |http|
      body = nil
      http.start do
        req = Net::HTTP::Get.new '/', {}
        http.request(req) { |resp| body = resp.body }
      end
      assert_equal 'https', body
    end
  end
end if ::Puma::HAS_SSL
