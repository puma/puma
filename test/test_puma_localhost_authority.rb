# Nothing in this file runs if Puma isn't compiled with ssl support
#
# helper is required first since it loads Puma, which needs to be
# loaded so HAS_SSL is defined
require_relative "helper"
require "localhost/authority"

if ::Puma::HAS_SSL && !Puma::IS_JRUBY
  require "puma/minissl"
  require "puma/events"
  require "net/http"

  class SSLEventsHelper < ::Puma::Events
    attr_accessor :addr, :cert, :error

    def ssl_error(error, ssl_socket)
      self.error = error
      self.addr = ssl_socket.peeraddr.last rescue "<unknown>"
      self.cert = ssl_socket.peercert
    end
  end


  # net/http (loaded in helper) does not necessarily load OpenSSL
  require "openssl" unless Object.const_defined? :OpenSSL


  puts "", RUBY_DESCRIPTION, "RUBYOPT: #{ENV['RUBYOPT']}",
       "                         Puma::MiniSSL                   OpenSSL",
       "OPENSSL_LIBRARY_VERSION: #{Puma::MiniSSL::OPENSSL_LIBRARY_VERSION.ljust 32}#{OpenSSL::OPENSSL_LIBRARY_VERSION}",
       "        OPENSSL_VERSION: #{Puma::MiniSSL::OPENSSL_VERSION.ljust 32}#{OpenSSL::OPENSSL_VERSION}", ""

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

  def test_url_scheme_for_https
    start_server
    body = nil
    @http.start do
      req = Net::HTTP::Get.new "/", {}
      @http.request(req) do |rep|
        body = rep.body
      end
    end

    assert_equal "https", body
  end

  def test_localhost_authority_generated
    # Initiate server to create localhost authority
    unless File.exist?(File.join(Localhost::Authority.path,"localhost.key"))
      start_server
    end
    assert_equal(File.exist?(File.join(Localhost::Authority.path,"localhost.key")), true)
    assert_equal(File.exist?(File.join(Localhost::Authority.path,"localhost.crt")), true)
  end

end if ::Puma::HAS_SSL

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

    local_authority_key = OpenSSL::PKey::RSA.new File.read(File.join(Localhost::Authority.path,"localhost.key"))
    local_authority_crt = OpenSSL::X509::Certificate.new File.read(File.join(Localhost::Authority.path,"localhost.crt"))

    @http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    @server.run
    @cert = nil
    client_error = false
    begin
      @http.start do
        req = Net::HTTP::Get.new "/", {}
        @http.request(req)
        @cert = @http.peer_cert
      end
    rescue OpenSSL::SSL::SSLError, EOFError, Errno::ECONNRESET => e
      # Errno::ECONNRESET TruffleRuby
      client_error = true
      # closes socket if open, may not close on error
      @http.send :do_finish
    end
    sleep 0.1

    assert_equal(@cert.to_pem, local_authority_crt.to_pem)
  end
end  if ::Puma::HAS_SSL && !Puma::IS_JRUBY
