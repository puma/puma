# frozen_string_literal: true

require_relative 'helper'
require_relative "helpers/test_puma/server_spawn"

# Session reuse is not currently supported with Puma's JRuby implementation

class TestIntegrationSSLSession < TestPuma::ServerSpawn
  parallelize_me! if Puma::IS_MRI

  require "openssl" unless defined?(::OpenSSL::SSL)

  OSSL = ::OpenSSL::SSL

  CLIENT_HAS_TLS1_3 = OSSL.const_defined? :TLS1_3_VERSION

  GET = "GET / HTTP/1.1\r\nConnection: close\r\n\r\n"

  RESP = "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 5\r\n\r\nhttps"

  def setup
    set_bind_type :ssl
    set_control_type :tcp
  end

  def set_reuse(reuse)
    cert_path = File.expand_path '../examples/puma/client-certs', __dir__

    <<~CONFIG
      ssl_bind '#{bind_host}', '#{bind_port}', {
        cert: '#{cert_path}/server.crt',
        key:  '#{cert_path}/server.key',
        ca:   '#{cert_path}/client-certs/ca.crt',
        verify_mode: 'none',
        reuse: #{reuse}
      }

      app do |env|
        [200, {}, [env['rack.url_scheme']]]
      end
    CONFIG
  end

  def run_session(reuse, tls = nil)
    config = set_reuse reuse
    server_spawn config: config, no_bind: true
    ssl_client tls_vers: tls
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

  def client_ctx(tls_vers = nil, session_pems = [], queue = nil)
    new_ctx do |ctx|
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
      ctx.session_new_cb = ->(ary) do
        queue << true if queue
        session_pems << ary.last.to_pem
      end
    end
  end

  def ssl_client(tls_vers: nil)
  queue = Thread::Queue.new
    session_pems = []
    ctx = client_ctx tls_vers, session_pems, queue
    socket = send_http GET, ctx: ctx
    assert_equal RESP, socket.read_response
    socket.sysclose
    queue.pop # wait for cb session to be added to first client

    ctx = client_ctx tls_vers, session_pems
    session = OSSL::Session.new session_pems[0]
    socket = send_http GET, ctx: ctx, session: session
    assert_equal RESP, socket.read_response
    socket.session_reused?
  end
end if Puma::HAS_SSL && Puma::IS_MRI
