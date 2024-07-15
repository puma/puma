# frozen_string_literal: true

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

  require "openssl" unless defined?(::OpenSSL::SSL)

  OSSL = ::OpenSSL::SSL

  CLIENT_HAS_TLS1_3 = OSSL.const_defined? :TLS1_3_VERSION

  GET = "GET / HTTP/1.1\r\nConnection: close\r\n\r\n"

  RESP = "HTTP/1.1 200 OK\r\nconnection: close\r\ncontent-length: 5\r\n\r\nhttps"

  CERT_PATH = File.expand_path "../examples/puma/client-certs", __dir__

  def teardown
    return if skipped?
    # stop server
    sock = TCPSocket.new HOST, control_tcp_port
    @ios_to_close << sock
    sock.syswrite "GET /stop?token=#{TOKEN} HTTP/1.1\r\n\r\n"
    sock.read
    assert_match 'Goodbye!', @server.read

    @server.close unless @server&.closed?
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
    <<~RUBY
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
    wait_for_server_to_boot log: false
    @pid = @server.pid

    yield
  end

  def run_session(reuse, tls = nil)
    config = set_reuse reuse

    with_server(config) { ssl_client tls_vers: tls }
  end

  def test_dflt
    reused = run_session true
    assert reused, 'session was not reused'
  end

  def test_dflt_tls1_2
    reused = run_session true, :TLS1_2
    assert reused, 'session was not reused'
  end

  def test_dflt_tls1_3
    skip 'TLSv1.3 unavailable' unless Puma::MiniSSL::HAS_TLS1_3 && CLIENT_HAS_TLS1_3
    reused = run_session true, :TLS1_3
    assert reused, 'session was not reused'
  end

  def test_1000_tls1_2
    reused = run_session '{size: 1_000}', :TLS1_2
    assert reused, 'session was not reused'
  end

  def test_1000_10_tls1_2
    reused = run_session '{size: 1000, timeout: 10}', :TLS1_2
    assert reused, 'session was not reused'
  end

  def test__10_tls1_2
    reused = run_session '{timeout: 10}', :TLS1_2
    assert reused, 'session was not reused'
  end

  def test_off_tls1_2
    ssl_vers = Puma::MiniSSL::OPENSSL_LIBRARY_VERSION
    old_ssl = ssl_vers.include?(' 1.0.') || ssl_vers.match?(/ 1\.1\.1[ a-e]/)
    skip 'Requires 1.1.1f or later' if old_ssl
    reused = run_session 'nil', :TLS1_2
    assert reused, 'session was not reused'
  end

  # TLSv1.3 reuse is always on
  def test_off_tls1_3
    skip 'TLSv1.3 unavailable' unless Puma::MiniSSL::HAS_TLS1_3 && CLIENT_HAS_TLS1_3
    reused = run_session 'nil'
    assert reused, 'TLSv1.3 session was not reused'
  end

  def client_skt(tls_vers = nil, session_pems = [], queue = nil)
    ctx = OSSL::SSLContext.new
    ctx.verify_mode = OSSL::VERIFY_NONE
    ctx.session_cache_mode = OSSL::SSLContext::SESSION_CACHE_CLIENT
    if tls_vers
      if ctx.respond_to? :max_version=
        ctx.max_version = tls_vers
        ctx.min_version = tls_vers
      else
        ctx.ssl_version = tls_vers.to_s.sub('TLS', 'TLSv').to_sym
      end
    end
    ctx.session_new_cb = ->(ary) {
      queue << true if queue
      session_pems << ary.last.to_pem
    }

    skt = OSSL::SSLSocket.new TCPSocket.new(HOST, bind_port), ctx
    skt.sync_close = true
    skt
  end

  def ssl_client(tls_vers: nil)
    queue = Thread::Queue.new
    session_pems = []
    skt = client_skt tls_vers, session_pems, queue
    skt.connect

    skt.syswrite GET
    skt.to_io.wait_readable 2
    assert_equal RESP, skt.sysread(1_024)
    skt.sysclose
    queue.pop # wait for cb session to be added to first client

    skt = client_skt tls_vers, session_pems
    skt.session = OSSL::Session.new(session_pems[0])
    skt.connect

    skt.syswrite GET
    skt.to_io.wait_readable 2
    assert_equal RESP, skt.sysread(1_024)
    queue.close
    queue = nil

    skt.session_reused?
  ensure
    skt&.sysclose unless skt&.closed?
  end
end if Puma::HAS_SSL && Puma::IS_MRI
