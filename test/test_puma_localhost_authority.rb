# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/test_puma/server_in_process"

# Nothing in this file runs if Puma isn't compiled with ssl support
#
# helper is required first since it loads Puma, which needs to be
# loaded so HAS_SSL is defined

if ::Puma::HAS_SSL && !Puma::IS_JRUBY
  require "localhost/authority"
  require "puma/minissl"
  require "openssl" unless Object.const_defined? :OpenSSL
end

class TestPumaLocalhostAuthority < TestPuma::ServerInProcess

  def setup
    @lha_path = Localhost::Authority.path
    @lha_cert_file = File.join @lha_path,"localhost.crt"
  end

  def start_server
    set_bind_type :ssl, host: LOCALHOST
    app = lambda { |env| [200, {}, [env['rack.url_scheme']]] }
    server_run app: app, ctx: false
  end

  def test_localhost_authority_file_generated
    # Initiate server to create localhost authority
    lha_key_file = File.join @lha_path, "localhost.key"
    unless File.exist? lha_key_file
      start_server
    end
    assert_operator File, :exist?, lha_key_file
    assert_operator File, :exist?, @lha_cert_file
  end

  def test_self_signed_by_localhost_authority
    start_server
    local_authority_crt = OpenSSL::X509::Certificate.new File.read @lha_cert_file

    cert = nil
    begin
      cert = send_http(ctx: new_ctx).peer_cert
    rescue OpenSSL::SSL::SSLError, EOFError, Errno::ECONNRESET
      # Errno::ECONNRESET TruffleRuby
    end
    sleep 0.1

    assert_equal cert.to_pem, local_authority_crt.to_pem
  end
end if ::Puma::HAS_SSL && !Puma::IS_JRUBY
