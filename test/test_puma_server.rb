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
    @server.stop(true)
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

  def test_proper_stringio_body
    data = nil

    @server.app = proc do |env|
      data = env['rack.input'].read
      [200, {}, ["ok"]]
    end

    @server.add_tcp_listener @host, @port
    @server.run

    fifteen = "1" * 15

    sock = TCPSocket.new @host, @port
    sock << "PUT / HTTP/1.0\r\nContent-Length: 30\r\n\r\n#{fifteen}"
    sleep 0.1 # important so that the previous data is sent as a packet
    sock << fifteen

    sock.read

    assert_equal "#{fifteen}#{fifteen}", data
  end

  def test_puma_socket
    body = "HTTP/1.1 750 Upgraded to Awesome\r\nDone: Yep!\r\n"
    @server.app = proc do |env|
      io = env['puma.socket']

      io.write body

      io.close

      [-1, {}, []]
    end

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @port
    sock << "PUT / HTTP/1.0\r\n\r\nHello"

    assert_equal body, sock.read
  end
end
