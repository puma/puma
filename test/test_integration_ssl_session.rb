require_relative 'helper'
require_relative 'helpers/integration'

# These tests are used to verify that Puma works with SSL sockets.  Only
# integration tests isolate the server from the test environment, so there
# should be a few SSL tests.
#
# For instance, since other tests make use of 'client' SSLSockets created by
# net/http, OpenSSL is loaded in the CI process.  By shelling out with IO.popen,
# the server process isn't affected by whatever is loaded in the CI process.

class TestIntegrationSSLSession < TestIntegration
  parallelize_me! if Puma::IS_MRI

  require "net/http"
  require "openssl"

  GET = "GET / HTTP/1.1\r\nConnection: close\r\n\r\n"

  RESP = "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 5\r\n\r\nhttps"

  CERT_PATH = File.expand_path "../examples/puma/client-certs", __dir__

  def teardown
    @server.close unless @server && @server.closed?
    @server = nil
    super
  end

  def bind_port
    @bind_port ||= UniquePort.call
  end

  def control_tcp_port
    @control_tcp_port ||= UniquePort.call
  end

  def set_reuse(reuse)
<<RUBY
  key  = '#{File.expand_path '../examples/puma/client-certs/server.key', __dir__}'
  cert = '#{File.expand_path '../examples/puma/client-certs/server.crt', __dir__}'
  ca   = '#{File.expand_path '../examples/puma/client-certs/ca.crt', __dir__}'

  ssl_bind '#{HOST}', '#{bind_port}', {
    cert: cert,
    key:  key,
    ca: ca,
    verify_mode: 'none',
    reuse: #{reuse}
  }

  activate_control_app 'tcp://#{HOST}:#{control_tcp_port}', { auth_token: '#{TOKEN}' }

  app do |env|
    [200, {}, [env['rack.url_scheme']]]
  end
RUBY
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

    yield

  ensure
    # stop server
    sock = TCPSocket.new HOST, control_tcp_port
    @ios_to_close << sock
    sock.syswrite "GET /stop?token=#{TOKEN} HTTP/1.1\r\n\r\n"
    sock.read
    assert_match 'Goodbye!', @server.read
  end

  def run_session(reuse, tls = nil)
    config = set_reuse reuse

    with_server(config) do

      uri = "https://#{HOST}:#{@bind_port}/"

      curl_cmd = %(curl -k -v --http1.1 -H "Connection: close" #{tls} #{uri} #{uri})

      curl = ''
      IO.popen(curl_cmd, :err=>[:child, :out]) { |io| curl = io.read }

      curl.include? '* SSL re-using session ID'
    end
  end

  def test_dflt
    reused = run_session true
    assert reused, 'session was not reused'
  end

  def test_dflt_tls1_2
    reused = run_session true, '--tls-max 1.2'
    assert reused, 'session was not reused'
  end

  def test_1000_tls1_2
    reused = run_session '{size: 1_000}', '--tls-max 1.2'
    assert reused, 'session was not reused'
  end

  def test_1000_10_tls1_2
    reused = run_session '{size: 1000, timeout: 10}', '--tls-max 1.2'
    assert reused, 'session was not reused'
  end

  def test__10_tls1_2
    reused = run_session '{timeout: 10}', '--tls-max 1.2'
    assert reused, 'session was not reused'
  end

  # session reuse has always worked with TLSv1.3
  def test_off_tls1_2
    ssl_vers = Puma::MiniSSL::OPENSSL_LIBRARY_VERSION
    old_ssl = ssl_vers.include?(' 1.0.') || ssl_vers.match?(/ 1\.1\.1[ a-e]/)
    skip 'Requires 1.1.1f or later' if old_ssl
    reused = run_session 'nil', '--tls-max 1.2'
    refute reused, 'session was reused'
  end

  def test_off_tls1_3
    skip 'TLSv1.3 unavailable' unless Puma::MiniSSL::HAS_TLS1_3
    reused = run_session 'nil'
    assert reused, 'TLSv1.3 session was not reused'
  end
end if Puma::HAS_SSL && Puma::IS_MRI
