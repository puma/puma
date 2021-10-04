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

  def setup
    @bind_port = UniquePort.call
    @control_tcp_port = UniquePort.call
    @default_config = <<RUBY
if ::Puma.jruby?
  keystore =  '#{File.expand_path '../examples/puma/keystore.jks', __dir__}'
  keystore_pass = 'jruby_puma'

  ssl_bind '#{HOST}', '#{@bind_port}', {
    keystore: keystore,
    keystore_pass:  keystore_pass,
    verify_mode: 'none'
  }
else
  key  = '#{File.expand_path '../examples/puma/puma_keypair.pem', __dir__}'
  cert = '#{File.expand_path '../examples/puma/cert_puma.pem', __dir__}'

  ssl_bind '#{HOST}', '#{@bind_port}', {
    cert: cert,
    key:  key,
    verify_mode: 'none'
  }
end

activate_control_app 'tcp://#{HOST}:#{@control_tcp_port}', { auth_token: '#{TOKEN}' }

app do |env|
  [200, {}, [env['rack.url_scheme']]]
end
RUBY

    @localhost_config = <<RUBY
require 'localhost'

ssl_bind '#{HOST}', '#{@bind_port}'

activate_control_app 'tcp://#{HOST}:#{@control_tcp_port}', { auth_token: '#{TOKEN}' }

app do |env|
  [200, {}, [env['rack.url_scheme']]]
end
RUBY

    super
  end

  def teardown
    @server.close unless @server.closed?
    @server = nil
    super
  end

  def generate_config(config)
    config_file = Tempfile.new %w(config .rb)
    config_file.write(config)
    config_file.close
    config_file.path
  end

  def start_server(cmd)
    @server = IO.popen cmd, 'r'
    wait_for_server_to_boot
    @pid = @server.pid

    @http = Net::HTTP.new HOST, @bind_port
    @http.use_ssl = true
    @http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  end

  def stop_server
    sock = TCPSocket.new HOST, @control_tcp_port
    @ios_to_close << sock
    sock.syswrite "GET /stop?token=#{TOKEN} HTTP/1.1\r\n\r\n"
    sock.read
    assert_match 'Goodbye!', @server.read
  end

  def test_ssl_run
    body = nil
    start_server("#{BASE} bin/puma -C #{generate_config(@default_config)}")
    @http.start do
      req = Net::HTTP::Get.new '/', {}
      @http.request(req) { |resp| body = resp.body }
    end
    assert_equal 'https', body
    stop_server
  end

  def test_ssl_run_with_localhost_authority
    skip_if :jruby

    body = nil
    start_server("#{BASE} bin/puma -C #{generate_config(@localhost_config)}")
    @http.start do
      req = Net::HTTP::Get.new '/', {}
      @http.request(req) { |resp| body = resp.body }
    end
    assert_equal 'https', body
    stop_server
  end
end if ::Puma::HAS_SSL
