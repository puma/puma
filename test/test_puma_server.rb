require "rbconfig"
require 'test/unit'
require 'socket'
require 'openssl'

require 'puma/server'

require 'net/https'

class TestPumaServer < Test::Unit::TestCase

  def setup
    @port = 3212
    @host = "127.0.0.1"

    @app = lambda { |env| [200, {}, [env['rack.url_scheme']]] }

    @events = Puma::Events.new STDOUT, STDERR
    @server = Puma::Server.new @app, @events

    @ssl_key =  File.expand_path "../../examples/puma/puma_keypair.pem", __FILE__
    @ssl_cert = File.expand_path "../../examples/puma/cert_puma.pem", __FILE__
  end

  def teardown
    @server.stop
  end

  def test_url_scheme_for_https
    ctx = OpenSSL::SSL::SSLContext.new

    ctx.key = OpenSSL::PKey::RSA.new File.read(@ssl_key)

    ctx.cert = OpenSSL::X509::Certificate.new File.read(@ssl_cert)

    ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE

    @server.add_ssl_listener @host, @port, ctx
    @server.run

    http = Net::HTTP.new @host, @port
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    body = nil
    http.start do
      req = Net::HTTP::Get.new "/", {}

      http.request(req) do |rep|
        body = rep.body
      end
    end

    assert_equal "https", body
  end
end
