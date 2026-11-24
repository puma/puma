# frozen_string_literal: true

# Nothing in this file runs if Puma isn't compiled with ssl support
#
# helper is required first since it loads Puma, which needs to be
# loaded so HAS_SSL is defined
require_relative "helper"
require "localhost/authority"

if ::Puma::HAS_SSL && !Puma::IS_JRUBY
  require "puma/minissl"
  require "puma/binder"
  require "puma/configuration"
  require_relative "helpers/test_puma/puma_socket"
  require "openssl" unless Object.const_defined? :OpenSSL
end

class TestPumaLocalhostAuthority < PumaTest
  include TestPuma
  include TestPuma::PumaSocket

  def setup
    @server = nil
  end

  def teardown
    @server&.stop true
  end

  # yields ctx to block, use for ctx setup & configuration
  def start_server
    app = lambda { |env| [200, {}, [env['rack.url_scheme']]] }

    @log_writer = SSLLogWriterHelper.new STDOUT, STDERR
    @server = Puma::Server.new app, nil, {log_writer: @log_writer}
    @server.add_ssl_listener LOCALHOST, 0, nil
    @bind_port = @server.connected_ports[0]
    @server.run
  end

  def test_localhost_authority_file_generated
    # Initiate server to create localhost authority
    unless File.exist?(File.join(Localhost::Authority.path,"localhost.key"))
      start_server
    end
    assert_equal(File.exist?(File.join(Localhost::Authority.path,"localhost.key")), true)
    assert_equal(File.exist?(File.join(Localhost::Authority.path,"localhost.crt")), true)
  end

end if ::Puma::HAS_SSL && !Puma::IS_JRUBY

class TestPumaLocalhostAuthorityBinder < PumaTest
  include TestPuma
  include TestPuma::PumaSocket

  CERT_PATH = File.expand_path "../examples/puma/client_certs", __dir__
  CA_PATH   = "#{CERT_PATH}/ca.crt"

  def setup
    @server = nil
    @binder = nil
  end

  def teardown
    @server&.stop true
    @binder&.close
  end

  def test_ssl_bind_without_cert_key_applies_verify_mode_force_peer_and_ca
    start_server "verify_mode=force_peer&ca=#{CA_PATH}"

    assert_raises(OpenSSL::SSL::SSLError, EOFError, IOError, Errno::ECONNABORTED, Errno::ECONNRESET) do
      send_http_read_response ctx: new_ctx
    end

    body = send_http_read_resp_body ctx: new_ctx { |ctx|
      ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
      ctx.key  = OpenSSL::PKey::RSA.new File.read("#{CERT_PATH}/client.key")
      ctx.cert = OpenSSL::X509::Certificate.new File.read("#{CERT_PATH}/client.crt")
    }

    assert_equal "https", body
  end

  def test_ssl_bind_without_cert_key_applies_no_tlsv1
    start_server "no_tlsv1=true"

    assert @binder.ios[0].instance_variable_get(:@ctx).no_tlsv1
  end

  def test_ssl_bind_without_cert_key_ignores_key_password_command
    start_server "key_password_command=false"

    assert_equal "https", send_http_read_resp_body(ctx: new_ctx)
  end

  def test_ssl_bind_without_cert_key_serves_localhost_certificate
    start_server ""

    cert = send_http(ctx: new_ctx).peer_cert
    local_authority_crt = OpenSSL::X509::Certificate.new File.read(Localhost::Authority.fetch.certificate_path)

    assert_equal cert.to_pem, local_authority_crt.to_pem
  end

  private

  def start_server(query)
    @log_writer = SSLLogWriterHelper.new STDOUT, STDERR

    config = Puma::Configuration.new
    config.clamp
    @binder = Puma::Binder.new(@log_writer, config.options)
    @binder.parse ["ssl://127.0.0.1:0?#{query}"], @log_writer

    app = ->(env) { [200, {}, [env['rack.url_scheme']]] }
    @server = Puma::Server.new app, nil, {log_writer: @log_writer}
    @server.app = app
    @server.inherit_binder @binder
    @bind_port = @server.connected_ports[0]
    @server.run
  end
end if ::Puma::HAS_SSL && !Puma::IS_JRUBY

class TestPumaSSLLocalhostAuthority < PumaTest
  include TestPuma
  include TestPuma::PumaSocket

  def test_self_signed_by_localhost_authority
    app = lambda { |env| [200, {}, [env['rack.url_scheme']]] }

    @log_writer = SSLLogWriterHelper.new STDOUT, STDERR

    @server = Puma::Server.new app, nil, {log_writer: @log_writer}
    @server.app = app

    @server.add_ssl_listener LOCALHOST, 0, nil
    @bind_port = @server.connected_ports[0]

    local_authority_crt = OpenSSL::X509::Certificate.new File.read(File.join(Localhost::Authority.path,"localhost.crt"))

    @server.run
    cert = nil
    begin
      cert = send_http(host: LOCALHOST, ctx: new_ctx).peer_cert
    rescue OpenSSL::SSL::SSLError, EOFError, Errno::ECONNRESET
      # Errno::ECONNRESET TruffleRuby
    end
    sleep 0.1

    assert_equal(cert.to_pem, local_authority_crt.to_pem)
  end
end if ::Puma::HAS_SSL && !Puma::IS_JRUBY
