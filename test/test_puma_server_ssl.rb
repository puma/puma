# Nothing in this file runs if Puma isn't compiled with ssl support
#
# helper is required first since it loads Puma, which needs to be
# loaded so HAS_SSL is defined
require_relative "helper"

if ::Puma::HAS_SSL
  require "puma/minissl"
  require "net/http"

  # net/http (loaded in helper) does not necessarily load OpenSSL
  require "openssl" unless Object.const_defined? :OpenSSL
  if Puma::IS_JRUBY
    puts "", RUBY_DESCRIPTION, "RUBYOPT: #{ENV['RUBYOPT']}",
      "                         OpenSSL",
      "OPENSSL_LIBRARY_VERSION: #{OpenSSL::OPENSSL_LIBRARY_VERSION}",
      "        OPENSSL_VERSION: #{OpenSSL::OPENSSL_VERSION}", ""
  else
    puts "", RUBY_DESCRIPTION, "RUBYOPT: #{ENV['RUBYOPT']}",
      "                         Puma::MiniSSL                   OpenSSL",
      "OPENSSL_LIBRARY_VERSION: #{Puma::MiniSSL::OPENSSL_LIBRARY_VERSION.ljust 32}#{OpenSSL::OPENSSL_LIBRARY_VERSION}",
      "        OPENSSL_VERSION: #{Puma::MiniSSL::OPENSSL_VERSION.ljust 32}#{OpenSSL::OPENSSL_VERSION}", ""
  end
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
    @host = "127.0.0.1"

    app = lambda { |env| [200, {}, [env['rack.url_scheme']]] }

    ctx = Puma::MiniSSL::Context.new

    if Puma.jruby?
      ctx.keystore =  File.expand_path "../examples/puma/keystore.jks", __dir__
      ctx.keystore_pass = 'jruby_puma'
    else
      ctx.key  =  File.expand_path "../examples/puma/puma_keypair.pem", __dir__
      ctx.cert = File.expand_path "../examples/puma/cert_puma.pem", __dir__
    end

    ctx.verify_mode = Puma::MiniSSL::VERIFY_NONE

    yield ctx if block_given?

    @events = SSLEventsHelper.new STDOUT, STDERR
    @server = Puma::Server.new app, @events
    @port = (@server.add_ssl_listener @host, 0, ctx).addr[1]
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
    port = @server.connected_ports[0]
    socket = OpenSSL::SSL::SSLSocket.new TCPSocket.new(@host, port), ctx
    socket.connect
    socket.write "HEAD"
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

    if OpenSSL::SSL::SSLContext.private_instance_methods(false).include?(:set_minmax_proto_version)
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

    if OpenSSL::SSL::SSLContext.private_instance_methods(false).include?(:set_minmax_proto_version)
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

  def test_http_rejection
    body_http  = nil
    body_https = nil

    start_server

    http = Net::HTTP.new @host, @server.connected_ports[0]
    http.use_ssl = false
    http.read_timeout = 6

    tcp = Thread.new do
      req_http = Net::HTTP::Get.new "/", {}
      # Net::ReadTimeout - TruffleRuby
      assert_raises(Errno::ECONNREFUSED, EOFError, Net::ReadTimeout, Net::OpenTimeout) do
        http.start.request(req_http) { |rep| body_http = rep.body }
      end
    end

    ssl = Thread.new do
      @http.start do
        req_https = Net::HTTP::Get.new "/", {}
        @http.request(req_https) { |rep_https| body_https = rep_https.body }
      end
    end

    tcp.join
    ssl.join
    http.finish
    sleep 1.0

    assert_nil body_http
    assert_equal "https", body_https

    thread_pool = @server.instance_variable_get(:@thread_pool)
    busy_threads = thread_pool.spawned - thread_pool.waiting

    assert busy_threads.zero?, "Our connection is wasn't dropped"
  end

  unless Puma.jruby?
    def test_invalid_cert
      assert_raises(Puma::MiniSSL::SSLError) do
        start_server { |ctx| ctx.cert = __FILE__ }
      end
    end

    def test_invalid_key
      assert_raises(Puma::MiniSSL::SSLError) do
        start_server { |ctx| ctx.key = __FILE__ }
      end
    end

    def test_invalid_cert_pem
      assert_raises(Puma::MiniSSL::SSLError) do
        start_server { |ctx|
          ctx.instance_variable_set(:@cert, nil)
          ctx.cert_pem = 'Not a valid pem'
        }
      end
    end

    def test_invalid_key_pem
      assert_raises(Puma::MiniSSL::SSLError) do
        start_server { |ctx|
          ctx.instance_variable_set(:@key, nil)
          ctx.key_pem = 'Not a valid pem'
        }
      end
    end

    def test_invalid_ca
      assert_raises(Puma::MiniSSL::SSLError) do
        start_server { |ctx|
          ctx.ca = __FILE__
        }
      end
    end
  end
end if ::Puma::HAS_SSL

# client-side TLS authentication tests
class TestPumaServerSSLClient < Minitest::Test
  parallelize_me! unless ::Puma.jruby?

  CERT_PATH = File.expand_path "../examples/puma/client-certs", __dir__

  # Context can be shared, may help with JRuby
  CTX = Puma::MiniSSL::Context.new.tap { |ctx|
    if Puma.jruby?
      ctx.keystore =  "#{CERT_PATH}/keystore.jks"
      ctx.keystore_pass = 'jruby_puma'
    else
      ctx.key  = "#{CERT_PATH}/server.key"
      ctx.cert = "#{CERT_PATH}/server.crt"
      ctx.ca   = "#{CERT_PATH}/ca.crt"
    end
    ctx.verify_mode = Puma::MiniSSL::VERIFY_PEER | Puma::MiniSSL::VERIFY_FAIL_IF_NO_PEER_CERT
  }

  def assert_ssl_client_error_match(error, subject=nil, &blk)
    host = "localhost"
    port = 0

    app = lambda { |env| [200, {}, [env['rack.url_scheme']]] }

    events = SSLEventsHelper.new STDOUT, STDERR
    server = Puma::Server.new app, events
    server.add_ssl_listener host, port, CTX
    host_addrs = server.binder.ios.map { |io| io.to_io.addr[2] }
    server.run

    http = Net::HTTP.new host, server.connected_ports[0]
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    yield http

    client_error = false
    begin
      http.start do
        req = Net::HTTP::Get.new "/", {}
        http.request(req)
      end
    rescue OpenSSL::SSL::SSLError, EOFError, Errno::ECONNRESET
      # Errno::ECONNRESET TruffleRuby
      client_error = true
      # closes socket if open, may not close on error
      http.send :do_finish
    end

    sleep 0.1
    assert_equal !!error, client_error
    # The JRuby MiniSSL implementation lacks error capturing currently,
    # so we can't inspect the messages here
    unless Puma.jruby?
      assert_match error, events.error.message if error
      assert_includes host_addrs, events.addr if error
      assert_equal subject, events.cert.subject.to_s if subject
    end
  ensure
    server.stop(true) if server
  end

  def test_verify_fail_if_no_client_cert
    assert_ssl_client_error_match 'peer did not return a certificate' do |http|
      # nothing
    end
  end

  def test_verify_fail_if_client_unknown_ca
    assert_ssl_client_error_match(/self[- ]signed certificate in certificate chain/, '/DC=net/DC=puma/CN=CAU') do |http|
      key = "#{CERT_PATH}/client_unknown.key"
      crt = "#{CERT_PATH}/client_unknown.crt"
      http.key = OpenSSL::PKey::RSA.new File.read(key)
      http.cert = OpenSSL::X509::Certificate.new File.read(crt)
      http.ca_file = "#{CERT_PATH}/unknown_ca.crt"
    end
  end

  def test_verify_fail_if_client_expired_cert
    assert_ssl_client_error_match('certificate has expired', '/DC=net/DC=puma/CN=localhost') do |http|
      key = "#{CERT_PATH}/client_expired.key"
      crt = "#{CERT_PATH}/client_expired.crt"
      http.key = OpenSSL::PKey::RSA.new File.read(key)
      http.cert = OpenSSL::X509::Certificate.new File.read(crt)
      http.ca_file = "#{CERT_PATH}/ca.crt"
    end
  end

  def test_verify_client_cert
    assert_ssl_client_error_match(nil) do |http|
      key = "#{CERT_PATH}/client.key"
      crt = "#{CERT_PATH}/client.crt"
      http.key = OpenSSL::PKey::RSA.new File.read(key)
      http.cert = OpenSSL::X509::Certificate.new File.read(crt)
      http.ca_file = "#{CERT_PATH}/ca.crt"
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    end
  end
end if ::Puma::HAS_SSL

class TestPumaServerSSLWithCertPemAndKeyPem < Minitest::Test
  CERT_PATH = File.expand_path "../examples/puma/client-certs", __dir__

  def test_server_ssl_with_cert_pem_and_key_pem
    host = "localhost"
    port = 0
    ctx = Puma::MiniSSL::Context.new.tap { |ctx|
      ctx.cert_pem = File.read("#{CERT_PATH}/server.crt")
      ctx.key_pem = File.read("#{CERT_PATH}/server.key")
    }

    app = lambda { |env| [200, {}, [env['rack.url_scheme']]] }
    events = SSLEventsHelper.new STDOUT, STDERR
    server = Puma::Server.new app, events
    server.add_ssl_listener host, port, ctx
    server.run

    http = Net::HTTP.new host, server.connected_ports[0]
    http.use_ssl = true
    http.ca_file = "#{CERT_PATH}/ca.crt"

    client_error = nil
    begin
      http.start do
        req = Net::HTTP::Get.new "/", {}
        http.request(req)
      end
    rescue OpenSSL::SSL::SSLError, EOFError, Errno::ECONNRESET => e
      # Errno::ECONNRESET TruffleRuby
      client_error = e
      # closes socket if open, may not close on error
      http.send :do_finish
    end

    assert_nil client_error
  ensure
    server.stop(true) if server
  end
end if ::Puma::HAS_SSL && !Puma::IS_JRUBY
