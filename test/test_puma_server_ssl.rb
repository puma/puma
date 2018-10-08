require_relative "helper"
require "puma/minissl"
require "puma/puma_http11"

#———————————————————————————————————————————————————————————————————————————————
#             NOTE: ALL TESTS BYPASSED IF DISABLE_SSL IS TRUE
#———————————————————————————————————————————————————————————————————————————————

class SSLEventsHelper < ::Puma::Events
  attr_accessor :addr, :cert, :error

  def ssl_error(server, peeraddr, peercert, error)
    self.addr = peeraddr
    self.cert = peercert
    self.error = error
  end
end

DISABLE_SSL = begin
              Puma::Server.class
              Puma::MiniSSL.check
              puts "", RUBY_DESCRIPTION
              puts "Puma::MiniSSL OPENSSL_LIBRARY_VERSION: #{Puma::MiniSSL::OPENSSL_LIBRARY_VERSION}",
                   "                      OPENSSL_VERSION: #{Puma::MiniSSL::OPENSSL_VERSION}", ""
            rescue
              true
            else
              false
            end

class TestPumaServerSSL < Minitest::Test

  def setup
    return if DISABLE_SSL
    port = UniquePort.call
    host = "127.0.0.1"

    app = lambda { |env| [200, {}, [env['rack.url_scheme']]] }

    ctx = Puma::MiniSSL::Context.new

    if Puma.jruby?
      ctx.keystore =  File.expand_path "../../examples/puma/keystore.jks", __FILE__
      ctx.keystore_pass = 'blahblah'
    else
      ctx.key  =  File.expand_path "../../examples/puma/puma_keypair.pem", __FILE__
      ctx.cert = File.expand_path "../../examples/puma/cert_puma.pem", __FILE__
    end

    ctx.verify_mode = Puma::MiniSSL::VERIFY_NONE

    @events = SSLEventsHelper.new STDOUT, STDERR
    @server = Puma::Server.new app, @events
    @ssl_listener = @server.add_ssl_listener host, port, ctx
    @server.run

    @http = Net::HTTP.new host, port
    @http.use_ssl = true
    @http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  end

  def teardown
    return if DISABLE_SSL
    @http.finish if @http.started?
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

  def test_ssl_v3_rejection
    @http.ssl_version= :SSLv3
    assert_raises(OpenSSL::SSL::SSLError) do
      @http.start do
        Net::HTTP::Get.new '/'
      end
    end
    unless Puma.jruby?
      assert_match(/wrong version number|no protocols available/, @events.error.message) if @events.error
    end
  end

end unless DISABLE_SSL

# client-side TLS authentication tests
class TestPumaServerSSLClient < Minitest::Test

  def assert_ssl_client_error_match(error, subject=nil, &blk)
    port = 3212
    host = "127.0.0.1"

    app = lambda { |env| [200, {}, [env['rack.url_scheme']]] }

    ctx = Puma::MiniSSL::Context.new
    if Puma.jruby?
      ctx.keystore =  File.expand_path "../../examples/puma/client-certs/keystore.jks", __FILE__
      ctx.keystore_pass = 'blahblah'
    else
      ctx.key = File.expand_path "../../examples/puma/client-certs/server.key", __FILE__
      ctx.cert = File.expand_path "../../examples/puma/client-certs/server.crt", __FILE__
      ctx.ca = File.expand_path "../../examples/puma/client-certs/ca.crt", __FILE__
    end
    ctx.verify_mode = Puma::MiniSSL::VERIFY_PEER | Puma::MiniSSL::VERIFY_FAIL_IF_NO_PEER_CERT

    events = SSLEventsHelper.new STDOUT, STDERR
    server = Puma::Server.new app, events
    ssl_listener = server.add_ssl_listener host, port, ctx
    server.run

    http = Net::HTTP.new host, port
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    yield http

    client_error = false
    begin
      http.start do
        req = Net::HTTP::Get.new "/", {}
        http.request(req)
      end
    rescue OpenSSL::SSL::SSLError, EOFError
      client_error = true
    end

    sleep 0.1
    assert_equal !!error, client_error
    # The JRuby MiniSSL implementation lacks error capturing currently, so we can't inspect the
    # messages here
    unless Puma.jruby?
      assert_match error, events.error.message if error
      assert_equal host, events.addr if error
      assert_equal subject, events.cert.subject.to_s if subject
    end
  ensure
    server.stop(true)
  end

  def test_verify_fail_if_no_client_cert
    return if DISABLE_SSL

    assert_ssl_client_error_match 'peer did not return a certificate' do |http|
      # nothing
    end
  end

  def test_verify_fail_if_client_unknown_ca
    return if DISABLE_SSL

    assert_ssl_client_error_match('self signed certificate in certificate chain', '/DC=net/DC=puma/CN=ca-unknown') do |http|
      key = File.expand_path "../../examples/puma/client-certs/client_unknown.key", __FILE__
      crt = File.expand_path "../../examples/puma/client-certs/client_unknown.crt", __FILE__
      http.key = OpenSSL::PKey::RSA.new File.read(key)
      http.cert = OpenSSL::X509::Certificate.new File.read(crt)
      http.ca_file = File.expand_path "../../examples/puma/client-certs/unknown_ca.crt", __FILE__
    end
  end

  def test_verify_fail_if_client_expired_cert
    return if DISABLE_SSL
    assert_ssl_client_error_match('certificate has expired', '/DC=net/DC=puma/CN=client-expired') do |http|
      key = File.expand_path "../../examples/puma/client-certs/client_expired.key", __FILE__
      crt = File.expand_path "../../examples/puma/client-certs/client_expired.crt", __FILE__
      http.key = OpenSSL::PKey::RSA.new File.read(key)
      http.cert = OpenSSL::X509::Certificate.new File.read(crt)
      http.ca_file = File.expand_path "../../examples/puma/client-certs/ca.crt", __FILE__
    end
  end

  def test_verify_client_cert
    return if DISABLE_SSL
    assert_ssl_client_error_match(nil) do |http|
      key = File.expand_path "../../examples/puma/client-certs/client.key", __FILE__
      crt = File.expand_path "../../examples/puma/client-certs/client.crt", __FILE__
      http.key = OpenSSL::PKey::RSA.new File.read(key)
      http.cert = OpenSSL::X509::Certificate.new File.read(crt)
      http.ca_file = File.expand_path "../../examples/puma/client-certs/ca.crt", __FILE__
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    end
  end
end unless DISABLE_SSL
