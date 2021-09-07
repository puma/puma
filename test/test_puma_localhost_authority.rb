# Nothing in this file runs if Puma isn't compiled with ssl support
#
# helper is required first since it loads Puma, which needs to be
# loaded so HAS_SSL is defined
require_relative "helper"
require "localhost/authority"

if ::Puma::HAS_SSL && !Puma::IS_JRUBY
  require "puma/minissl"
  require "net/http"

  # net/http (loaded in helper) does not necessarily load OpenSSL
  require "openssl" unless Object.const_defined? :OpenSSL
end

class TestPumaLocalhostAuthority < Minitest::Test
  parallelize_me!
  def setup
    @http = nil
    @server = nil
  end

  def teardown
    @http.finish if @http && @http.started?
    @server.stop(true) if @server
  end

  # yields ctx to block, use for ctx setup & configuration
  def start_server
    @host = "localhost"
    app = lambda { |env| [200, {}, [env['rack.url_scheme']]] }

    @events = SSLEventsHelper.new STDOUT, STDERR
    @server = Puma::Server.new app, @events
    @server.app = app
    @server.add_ssl_listener @host, 0,nil
    @http = Net::HTTP.new @host, @server.connected_ports[0]

    @http.use_ssl = true
    # Disabling verification since its self signed
    @http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    # @http.verify_mode = OpenSSL::SSL::VERIFY_NONE

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

end if ::Puma::HAS_SSL &&  !Puma::IS_JRUBY

class TestPumaSSLLocalhostAuthority < Minitest::Test
  def test_self_signed_by_localhost_authority
    @host = "localhost"

    app = lambda { |env| [200, {}, [env['rack.url_scheme']]] }

    @events = SSLEventsHelper.new STDOUT, STDERR

    @server = Puma::Server.new app, @events
    @server.app = app

    @server.add_ssl_listener @host, 0,nil

    @http = Net::HTTP.new @host, @server.connected_ports[0]
    @http.use_ssl = true

    OpenSSL::PKey::RSA.new File.read(File.join(Localhost::Authority.path,"localhost.key"))
    local_authority_crt = OpenSSL::X509::Certificate.new File.read(File.join(Localhost::Authority.path,"localhost.crt"))

    @http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    @server.run
    @cert = nil
    begin
      @http.start do
        req = Net::HTTP::Get.new "/", {}
        @http.request(req)
        @cert = @http.peer_cert
      end
    rescue OpenSSL::SSL::SSLError, EOFError, Errno::ECONNRESET
      # Errno::ECONNRESET TruffleRuby
      # closes socket if open, may not close on error
      @http.send :do_finish
    end
    sleep 0.1

    assert_equal(@cert.to_pem, local_authority_crt.to_pem)
  end
end  if ::Puma::HAS_SSL && !Puma::IS_JRUBY
