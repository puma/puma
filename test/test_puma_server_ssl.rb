require "rbconfig"
require 'test/unit'
require 'socket'
require 'openssl'

require 'puma/minissl'
require 'puma/server'

require 'net/https'

class TestPumaServerSSL < Test::Unit::TestCase

  def setup
    @port = 3212
    @host = "127.0.0.1"

    @app = lambda { |env| [200, {}, [env['rack.url_scheme']]] }

    @ctx = Puma::MiniSSL::Context.new

    if defined?(JRUBY_VERSION)
      @ctx.keystore =  File.expand_path "../../examples/puma/keystore.jks", __FILE__
      @ctx.keystore_pass = 'blahblah'
    else
      @ctx.key =  File.expand_path "../../examples/puma/puma_keypair.pem", __FILE__
      @ctx.cert = File.expand_path "../../examples/puma/cert_puma.pem", __FILE__
    end

    @ctx.verify_mode = Puma::MiniSSL::VERIFY_NONE

    @events = Puma::Events.new STDOUT, STDERR
    @server = Puma::Server.new @app, @events
    @server.add_ssl_listener @host, @port, @ctx
    @server.run

    @http = Net::HTTP.new @host, @port
    @http.use_ssl = true
    @http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  end

  def teardown
    @server.stop(true)
  end

  def test_url_scheme_for_https
    body = nil
    @http.start do
      req = Net::HTTP::Get.new "/", {}

      @http.request(req) do |rep|
        body = rep.body
      end
    end

    assert_equal "https", body
  end

  def test_very_large_return
    giant = "x" * 2056610

    @server.app = proc do
      [200, {}, [giant]]
    end

    body = nil
    @http.start do
      req = Net::HTTP::Get.new "/"
      @http.request(req) do |rep|
        body = rep.body
      end
    end

    assert_equal giant.bytesize, body.bytesize
  end

  def test_form_submit
    body = nil
    @http.start do
      req = Net::HTTP::Post.new '/'
      req.set_form_data('a' => '1', 'b' => '2')

      @http.request(req) do |rep|
        body = rep.body
      end

    end

    assert_equal "https", body
  end

  if defined?(JRUBY_VERSION)
    def test_ssl_v3_support_disabled_by_default
      @http.ssl_version='SSLv3'
      assert_raises(OpenSSL::SSL::SSLError) do
        @http.start do
          Net::HTTP::Get.new '/'
        end
      end
    end

    def test_enabling_ssl_v3_support
      @server.stop(true)
      @ctx.enable_SSLv3 = true
      @server = Puma::Server.new @app, @events
      @server.add_ssl_listener @host, @port, @ctx
      @server.run
      @http.ssl_version='SSLv3'

      body = nil
      @http.start do
        req = Net::HTTP::Get.new "/", {}

        @http.request(req) do |rep|
          body = rep.body
        end
      end

      assert_equal "https", body
    end

    def test_enabling_ssl_v3_support_requires_true
      @server.stop(true)
      @ctx.enable_SSLv3 = "truthy but not true"
      @server = Puma::Server.new @app, @events
      @server.add_ssl_listener @host, @port, @ctx
      @server.run
      @http.ssl_version='SSLv3'

      assert_raises(OpenSSL::SSL::SSLError) do
        @http.start do
          Net::HTTP::Get.new '/'
        end
      end
    end
  end

end