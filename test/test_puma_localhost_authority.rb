# Nothing in this file runs if Puma isn't compiled with ssl support
#
# helper is required first since it loads Puma, which needs to be
# loaded so HAS_SSL is defined
require_relative "helper"
require "localhost/authority"

if ::Puma::HAS_SSL && !Puma::IS_JRUBY
  require "puma/minissl"
  require_relative "helpers/test_puma/puma_socket"
  require "openssl" unless Object.const_defined? :OpenSSL
end

class TestPumaLocalhostAuthority < Minitest::Test
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

class TestPumaSSLLocalhostAuthority < Minitest::Test
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
