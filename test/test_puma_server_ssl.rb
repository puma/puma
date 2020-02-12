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
              # net/http (loaded in helper) does not necessarily load OpenSSL
              require "openssl" unless Object.const_defined? :OpenSSL
              puts "", RUBY_DESCRIPTION,
                   "                         Puma::MiniSSL                   OpenSSL",
                   "OPENSSL_LIBRARY_VERSION: #{Puma::MiniSSL::OPENSSL_LIBRARY_VERSION.ljust 32}#{OpenSSL::OPENSSL_LIBRARY_VERSION}",
                   "        OPENSSL_VERSION: #{Puma::MiniSSL::OPENSSL_VERSION.ljust 32}#{OpenSSL::OPENSSL_VERSION}", ""
            rescue
              true
            else
              false
            end

class TestPumaServerSSL < Minitest::Test
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
    @port = UniquePort.call
    @host = "127.0.0.1"

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

    yield ctx if block_given?

    @events = SSLEventsHelper.new STDOUT, STDERR
    @server = Puma::Server.new app, @events
    @ssl_listener = @server.add_ssl_listener @host, @port, ctx
    @server.run

    @http = Net::HTTP.new @host, @port
    @http.use_ssl = true
    @http.verify_mode = OpenSSL::SSL::VERIFY_NONE
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

  def test_request_wont_block_thread
    start_server
    # Open a connection and give enough data to trigger a read, then wait
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
    socket = OpenSSL::SSL::SSLSocket.new TCPSocket.new(@host, @port), ctx
    socket.write "x"
    sleep 0.1

    # Capture the amount of threads being used after connecting and being idle
    thread_pool = @server.instance_variable_get(:@thread_pool)
    busy_threads = thread_pool.spawned - thread_pool.waiting

    socket.close

    # The thread pool should be empty since the request would block on read
    # and our request should have been moved to the reactor.
    assert busy_threads.zero?, "Our connection is monopolizing a thread"
  end

  def test_very_large_return
    start_server
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
    start_server
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
    skip("SSLv3 protocol is unavailable") if Puma::MiniSSL::OPENSSL_NO_SSL3
    start_server
    @http.ssl_version= :SSLv3
    # Ruby 2.4.5 on Travis raises ArgumentError
    assert_raises(OpenSSL::SSL::SSLError, ArgumentError) do
      @http.start do
        Net::HTTP::Get.new '/'
      end
    end
    unless Puma.jruby?
      msg = /wrong version number|no protocols available|version too low|unknown SSL method/
      assert_match(msg, @events.error.message) if @events.error
    end
  end

  def test_tls_v1_rejection
    skip("TLSv1 protocol is unavailable") if Puma::MiniSSL::OPENSSL_NO_TLS1
    start_server { |ctx| ctx.no_tlsv1 = true }

    if @http.respond_to? :max_version=
      @http.max_version = :TLS1
    else
      @http.ssl_version = :TLSv1
    end
    # Ruby 2.4.5 on Travis raises ArgumentError
    assert_raises(OpenSSL::SSL::SSLError, ArgumentError) do
      @http.start do
        Net::HTTP::Get.new '/'
      end
    end
    unless Puma.jruby?
      msg = /wrong version number|(unknown|unsupported) protocol|no protocols available|version too low|unknown SSL method/
      assert_match(msg, @events.error.message) if @events.error
    end
  end

  def test_tls_v1_1_rejection
    start_server { |ctx| ctx.no_tlsv1_1 = true }

    if @http.respond_to? :max_version=
      @http.max_version = :TLS1_1
    else
      @http.ssl_version = :TLSv1_1
    end
    # Ruby 2.4.5 on Travis raises ArgumentError
    assert_raises(OpenSSL::SSL::SSLError, ArgumentError) do
      @http.start do
        Net::HTTP::Get.new '/'
      end
    end
    unless Puma.jruby?
      msg = /wrong version number|(unknown|unsupported) protocol|no protocols available|version too low|unknown SSL method/
      assert_match(msg, @events.error.message) if @events.error
    end
  end
end unless DISABLE_SSL

# client-side TLS authentication tests
class TestPumaServerSSLClient < Minitest::Test
  parallelize_me!
  def assert_ssl_client_error_match(error, subject=nil, &blk)
    host = "127.0.0.1"
    port = UniquePort.call

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
    server.add_ssl_listener host, port, ctx
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
      # closes socket if open, may not close on error
      http.send :do_finish
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
    assert_ssl_client_error_match 'peer did not return a certificate' do |http|
      # nothing
    end
  end

  def test_verify_fail_if_client_unknown_ca
    assert_ssl_client_error_match('self signed certificate in certificate chain', '/DC=net/DC=puma/CN=ca-unknown') do |http|
      key = File.expand_path "../../examples/puma/client-certs/client_unknown.key", __FILE__
      crt = File.expand_path "../../examples/puma/client-certs/client_unknown.crt", __FILE__
      http.key = OpenSSL::PKey::RSA.new File.read(key)
      http.cert = OpenSSL::X509::Certificate.new File.read(crt)
      http.ca_file = File.expand_path "../../examples/puma/client-certs/unknown_ca.crt", __FILE__
    end
  end

  def test_verify_fail_if_client_expired_cert
    assert_ssl_client_error_match('certificate has expired', '/DC=net/DC=puma/CN=client-expired') do |http|
      key = File.expand_path "../../examples/puma/client-certs/client_expired.key", __FILE__
      crt = File.expand_path "../../examples/puma/client-certs/client_expired.crt", __FILE__
      http.key = OpenSSL::PKey::RSA.new File.read(key)
      http.cert = OpenSSL::X509::Certificate.new File.read(crt)
      http.ca_file = File.expand_path "../../examples/puma/client-certs/ca.crt", __FILE__
    end
  end

  def test_verify_client_cert
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
