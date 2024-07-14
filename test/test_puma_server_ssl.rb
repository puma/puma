# Nothing in this file runs if Puma isn't compiled with ssl support
#
# helper is required first since it loads Puma, which needs to be
# loaded so HAS_SSL is defined
require_relative "helper"

if ::Puma::HAS_SSL
  require "puma/minissl"
  require_relative "helpers/test_puma/puma_socket"

  if ENV['PUMA_TEST_DEBUG']
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
end

class TestPumaServerSSL < Minitest::Test
  parallelize_me!

  include TestPuma
  include TestPuma::PumaSocket

  PROTOCOL_USE_MIN_MAX =
    OpenSSL::SSL::SSLContext.private_instance_methods(false).include?(:set_minmax_proto_version)

  OPENSSL_3 = OpenSSL::OPENSSL_LIBRARY_VERSION.match?(/OpenSSL 3\.\d\.\d/)

  def setup
    @server = nil
  end

  def teardown
    @server&.stop true
  end

  # yields ctx to block, use for ctx setup & configuration
  def start_server
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

    @log_writer = SSLLogWriterHelper.new STDOUT, STDERR
    @server = Puma::Server.new app, nil, {log_writer: @log_writer}
    @port = (@server.add_ssl_listener HOST, 0, ctx).addr[1]
    @bind_port = @port
    @server.run
  end

  def test_url_scheme_for_https
    start_server
    assert_equal "https", send_http_read_resp_body(ctx: new_ctx)
  end

  def test_request_wont_block_thread
    start_server
    # Open a connection and give enough data to trigger a read, then wait
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
    @bind_port = @server.connected_ports[0]

    socket = send_http "HEAD",  ctx: new_ctx
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

    @server.app = proc { [200, {}, [giant]] }

    body = send_http_read_resp_body(ctx: new_ctx)

    assert_equal giant.bytesize, body.bytesize
  end

  def test_form_submit
    start_server
    @server.app = proc { |env| [200, {}, [env['rack.url_scheme'], "\n", env['rack.input'].read]] }

    req = "POST / HTTP/1.1\r\nContent-Type: text/plain\r\nContent-Length: 7\r\n\r\na=1&b=2"

    body = send_http_read_resp_body req, ctx: new_ctx

    assert_equal "https\na=1&b=2", body
  end

  def test_ssl_v3_rejection
    skip("SSLv3 protocol is unavailable") if Puma::MiniSSL::OPENSSL_NO_SSL3
    start_server

    assert_raises(OpenSSL::SSL::SSLError) do
      send_http_read_resp_body ctx: new_ctx { |c| c.ssl_version = :SSLv3 }
    end
    unless Puma.jruby?
      msg = /wrong version number|no protocols available|version too low|unknown SSL method/
      assert_match(msg, @log_writer.error.message) if @log_writer.error
    end
  end

  def test_tls_v1_rejection
    start_server { |ctx| ctx.no_tlsv1 = true }

    assert_raises(OpenSSL::SSL::SSLError) do
      send_http_read_resp_body ctx: new_ctx { |c|
        if PROTOCOL_USE_MIN_MAX
          c.max_version = :TLS1
        else
          c.ssl_version = :TLSv1
        end
      }
    end
    unless Puma.jruby?
      msg = /wrong version number|(unknown|unsupported) protocol|no protocols available|version too low|unknown SSL method/
      assert_match(msg, @log_writer.error.message) if @log_writer.error
    end
  end

  def test_tls_v1_1_rejection
    start_server { |ctx| ctx.no_tlsv1_1 = true }

    assert_raises(OpenSSL::SSL::SSLError) do
      send_http_read_response ctx: new_ctx { |c|
        if PROTOCOL_USE_MIN_MAX
          c.max_version = :TLS1_1
        else
          c.ssl_version = :TLSv1_1
        end
      }
    end
    unless Puma.jruby?
      msg = /wrong version number|(unknown|unsupported) protocol|no protocols available|version too low|unknown SSL method/
      assert_match(msg, @log_writer.error.message) if @log_writer.error
    end
  end

  def test_tls_v1_3
    skip("TLSv1.3 protocol can not be set") unless OpenSSL::SSL::SSLContext.instance_methods(false).include?(:min_version=)

    start_server

    body = send_http_read_resp_body ctx: new_ctx { |c|
      if PROTOCOL_USE_MIN_MAX
        c.min_version = :TLS1_3
      else
        c.ssl_version = :TLSv1_3
      end
    }

    assert_equal "https", body
  end

  def test_http_rejection
    body_http  = nil
    body_https = nil

    start_server

    tcp = Thread.new do
      assert_raises(Errno::ECONNREFUSED, EOFError, Timeout::Error) do
        body_http = send_http_read_resp_body timeout: 4
      end
    end

    ssl = Thread.new do
      body_https = send_http_read_resp_body ctx: new_ctx
    end

    tcp.join
    ssl.join
    sleep 1.0

    assert_nil body_http
    assert_equal "https", body_https

    thread_pool = @server.instance_variable_get(:@thread_pool)
    busy_threads = thread_pool.spawned - thread_pool.waiting

    assert busy_threads.zero?, "Our connection wasn't dropped"
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

    # this may require updates if TLSv1.3 default ciphers change
    def test_ssl_ciphersuites
      skip('Requires TLSv1.3') unless Puma::MiniSSL::HAS_TLS1_3

      start_server
      default_cipher = send_http(ctx: new_ctx).cipher[0]
      @server&.stop true

      cipher_suite = 'TLS_CHACHA20_POLY1305_SHA256'
      start_server { |ctx| ctx.ssl_ciphersuites = cipher_suite}

      cipher = send_http(ctx: new_ctx).cipher

      refute_equal default_cipher, cipher[0]
      assert_equal cipher_suite  , cipher[0]
      assert_equal cipher[1], 'TLSv1.3'
    end
  end
end if ::Puma::HAS_SSL

# client-side TLS authentication tests
class TestPumaServerSSLClient < Minitest::Test
  parallelize_me! unless ::Puma.jruby?

  include TestPuma
  include TestPuma::PumaSocket

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

  def assert_ssl_client_error_match(error, subject: nil, context: CTX, &blk)
    port = 0

    app = lambda { |env| [200, {}, [env['rack.url_scheme']]] }

    log_writer = SSLLogWriterHelper.new STDOUT, STDERR
    server = Puma::Server.new app, nil, {log_writer: log_writer}
    server.add_ssl_listener LOCALHOST, port, context
    host_addrs = server.binder.ios.map { |io| io.to_io.addr[2] }
    @bind_port = server.connected_ports[0]
    server.run

    ctx = OpenSSL::SSL::SSLContext.new
    yield ctx

    expected_errors = [
      EOFError,
      IOError,
      OpenSSL::SSL::SSLError,
      Errno::ECONNABORTED,
      Errno::ECONNRESET
    ]

    client_error = false
    begin
      send_http_read_resp_body host: LOCALHOST, ctx: ctx
    rescue *expected_errors => e
      client_error = e
    end

    sleep 0.1
    assert_equal !!error, !!client_error, client_error
    if error && !error.eql?(true)
      assert_match error, log_writer.error.message
      assert_includes host_addrs, log_writer.addr
    end
    assert_equal subject, log_writer.cert.subject.to_s if subject
  ensure
    server&.stop true
  end

  def test_verify_fail_if_no_client_cert
    error = Puma.jruby? ? /Empty client certificate chain/ : 'peer did not return a certificate'
    assert_ssl_client_error_match(error) do |client_ctx|
      # nothing
    end
  end

  def test_verify_fail_if_client_unknown_ca
    error = Puma.jruby? ? /No trusted certificate found/ : /self[- ]signed certificate in certificate chain/
    cert_subject = Puma.jruby? ? '/DC=net/DC=puma/CN=localhost' : '/DC=net/DC=puma/CN=CAU'
    assert_ssl_client_error_match(error, subject: cert_subject) do |client_ctx|
      key = "#{CERT_PATH}/client_unknown.key"
      crt = "#{CERT_PATH}/client_unknown.crt"
      client_ctx.key = OpenSSL::PKey::RSA.new File.read(key)
      client_ctx.cert = OpenSSL::X509::Certificate.new File.read(crt)
      client_ctx.ca_file = "#{CERT_PATH}/unknown_ca.crt"
    end
  end

  def test_verify_fail_if_client_expired_cert
    error = Puma.jruby? ? /NotAfter:/ : 'certificate has expired'
    assert_ssl_client_error_match(error, subject: '/DC=net/DC=puma/CN=localhost') do |client_ctx|
      key = "#{CERT_PATH}/client_expired.key"
      crt = "#{CERT_PATH}/client_expired.crt"
      client_ctx.key = OpenSSL::PKey::RSA.new File.read(key)
      client_ctx.cert = OpenSSL::X509::Certificate.new File.read(crt)
      client_ctx.ca_file = "#{CERT_PATH}/ca.crt"
    end
  end

  def test_verify_client_cert
    assert_ssl_client_error_match(false) do |client_ctx|
      key = "#{CERT_PATH}/client.key"
      crt = "#{CERT_PATH}/client.crt"
      client_ctx.key = OpenSSL::PKey::RSA.new File.read(key)
      client_ctx.cert = OpenSSL::X509::Certificate.new File.read(crt)
      client_ctx.ca_file = "#{CERT_PATH}/ca.crt"
      client_ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
    end
  end

  def test_verify_client_cert_with_truststore
    ctx = Puma::MiniSSL::Context.new
    ctx.keystore = "#{CERT_PATH}/server.p12"
    ctx.keystore_type = 'pkcs12'
    ctx.keystore_pass = 'jruby_puma'
    ctx.truststore =  "#{CERT_PATH}/ca_store.p12"
    ctx.truststore_type = 'pkcs12'
    ctx.truststore_pass = 'jruby_puma'
    ctx.verify_mode = Puma::MiniSSL::VERIFY_PEER

    assert_ssl_client_error_match(false, context: ctx) do |client_ctx|
      key = "#{CERT_PATH}/client.key"
      crt = "#{CERT_PATH}/client.crt"
      client_ctx.key = OpenSSL::PKey::RSA.new File.read(key)
      client_ctx.cert = OpenSSL::X509::Certificate.new File.read(crt)
      client_ctx.ca_file = "#{CERT_PATH}/ca.crt"
      client_ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
    end
  end if Puma.jruby?

  def test_verify_client_cert_without_truststore
    ctx = Puma::MiniSSL::Context.new
    ctx.keystore = "#{CERT_PATH}/server.p12"
    ctx.keystore_type = 'pkcs12'
    ctx.keystore_pass = 'jruby_puma'
    ctx.truststore = "#{CERT_PATH}/unknown_ca_store.p12"
    ctx.truststore_type = 'pkcs12'
    ctx.truststore_pass = 'jruby_puma'
    ctx.verify_mode = Puma::MiniSSL::VERIFY_PEER

    assert_ssl_client_error_match(true, context: ctx) do |client_ctx|
      key = "#{CERT_PATH}/client.key"
      crt = "#{CERT_PATH}/client.crt"
      client_ctx.key = OpenSSL::PKey::RSA.new File.read(key)
      client_ctx.cert = OpenSSL::X509::Certificate.new File.read(crt)
      client_ctx.ca_file = "#{CERT_PATH}/ca.crt"
      client_ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
    end
  end if Puma.jruby?

  def test_allows_using_default_truststore
    ctx = Puma::MiniSSL::Context.new
    ctx.keystore = "#{CERT_PATH}/server.p12"
    ctx.keystore_type = 'pkcs12'
    ctx.keystore_pass = 'jruby_puma'
    ctx.truststore = :default
    # NOTE: a little hard to test - we're at least asserting that setting :default does not raise errors
    ctx.verify_mode = Puma::MiniSSL::VERIFY_NONE

    assert_ssl_client_error_match(false, context: ctx) do |client_ctx|
      key = "#{CERT_PATH}/client.key"
      crt = "#{CERT_PATH}/client.crt"
      client_ctx.key = OpenSSL::PKey::RSA.new File.read(key)
      client_ctx.cert = OpenSSL::X509::Certificate.new File.read(crt)
      client_ctx.ca_file = "#{CERT_PATH}/ca.crt"
      client_ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
    end
  end if Puma.jruby?

  def test_allows_to_specify_cipher_suites_and_protocols
    ctx = CTX.dup
    ctx.cipher_suites = [ 'TLS_RSA_WITH_AES_128_GCM_SHA256' ]
    ctx.protocols = 'TLSv1.2'

    assert_ssl_client_error_match(false, context: ctx) do |client_ctx|
      key = "#{CERT_PATH}/client.key"
      crt = "#{CERT_PATH}/client.crt"
      client_ctx.key = OpenSSL::PKey::RSA.new File.read(key)
      client_ctx.cert = OpenSSL::X509::Certificate.new File.read(crt)
      client_ctx.ca_file = "#{CERT_PATH}/ca.crt"
      client_ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER

      client_ctx.ssl_version = :TLSv1_2
      client_ctx.ciphers = [ 'TLS_RSA_WITH_AES_128_GCM_SHA256' ]
    end
  end if Puma.jruby?

  def test_fails_when_no_cipher_suites_in_common
    ctx = CTX.dup
    ctx.cipher_suites = [ 'TLS_RSA_WITH_AES_128_GCM_SHA256' ]
    ctx.protocols = 'TLSv1.2'

    assert_ssl_client_error_match(/no cipher suites in common/, context: ctx) do |client_ctx|
      key = "#{CERT_PATH}/client.key"
      crt = "#{CERT_PATH}/client.crt"
      client_ctx.key = OpenSSL::PKey::RSA.new File.read(key)
      client_ctx.cert = OpenSSL::X509::Certificate.new File.read(crt)
      client_ctx.ca_file = "#{CERT_PATH}/ca.crt"
      client_ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER

      client_ctx.ssl_version = :TLSv1_2
      client_ctx.ciphers = [ 'TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384' ]
    end
  end if Puma.jruby?

  def test_verify_client_cert_with_truststore_without_pass
    ctx = Puma::MiniSSL::Context.new
    ctx.keystore = "#{CERT_PATH}/server.p12"
    ctx.keystore_type = 'pkcs12'
    ctx.keystore_pass = 'jruby_puma'
    ctx.truststore =  "#{CERT_PATH}/ca_store.jks" # cert entry can be read without password
    ctx.truststore_type = 'jks'
    ctx.verify_mode = Puma::MiniSSL::VERIFY_PEER

    assert_ssl_client_error_match(false, context: ctx) do |client_ctx|
      key = "#{CERT_PATH}/client.key"
      crt = "#{CERT_PATH}/client.crt"
      client_ctx.key = OpenSSL::PKey::RSA.new File.read(key)
      client_ctx.cert = OpenSSL::X509::Certificate.new File.read(crt)
      client_ctx.ca_file = "#{CERT_PATH}/ca.crt"
      client_ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
    end
  end if Puma.jruby?

end if ::Puma::HAS_SSL

class TestPumaServerSSLWithCertPemAndKeyPem < Minitest::Test
  include TestPuma
  include TestPuma::PumaSocket

  CERT_PATH = File.expand_path "../examples/puma/client-certs", __dir__

  def test_server_ssl_with_cert_pem_and_key_pem
    ctx = Puma::MiniSSL::Context.new
    ctx.cert_pem = File.read "#{CERT_PATH}/server.crt"
    ctx.key_pem  = File.read "#{CERT_PATH}/server.key"

    app = lambda { |env| [200, {}, [env['rack.url_scheme']]] }
    log_writer = SSLLogWriterHelper.new STDOUT, STDERR
    server = Puma::Server.new app, nil, {log_writer: log_writer}
    server.add_ssl_listener LOCALHOST, 0, ctx
    @bind_port = server.connected_ports[0]
    server.run

    client_error = nil
    begin
      send_http_read_resp_body host: LOCALHOST, ctx: new_ctx { |c|
        c.ca_file = "#{CERT_PATH}/ca.crt"
        c.verify_mode = OpenSSL::SSL::VERIFY_PEER
      }
    rescue OpenSSL::SSL::SSLError, EOFError, Errno::ECONNRESET => e
      # Errno::ECONNRESET TruffleRuby
      client_error = e
    end

    assert_nil client_error
  ensure
    server&.stop true
  end
end if ::Puma::HAS_SSL && !Puma::IS_JRUBY

#
# Test certificate chain support, The certs and the whole certificate chain for
# this tests are located in ../examples/puma/chain_cert and were generated with
# the following commands:
#
#   bundle exec ruby ../examples/puma/chain_cert/generate_chain_test.rb
#
class TestPumaSSLCertChain < Minitest::Test
  include TestPuma
  include TestPuma::PumaSocket

  CHAIN_DIR = File.expand_path '../examples/puma/chain_cert', __dir__

  # OpenSSL::X509::Name#to_utf8 only available in Ruby 2.5 and later
  USE_TO_UTFT8 = OpenSSL::X509::Name.instance_methods(false).include? :to_utf8

  def cert_chain(&blk)
    app = lambda { |env| [200, {}, [env['rack.url_scheme']]] }

    @log_writer = SSLLogWriterHelper.new STDOUT, STDERR
    @server = Puma::Server.new app, nil, {log_writer: @log_writer}

    mini_ctx = Puma::MiniSSL::Context.new
    mini_ctx.key  = "#{CHAIN_DIR}/cert.key"
    yield mini_ctx

    @bind_port = (@server.add_ssl_listener HOST, 0, mini_ctx).addr[1]
    @server.run

    socket = new_socket ctx: new_ctx

    subj_chain = socket.peer_cert_chain.map(&:subject)
    subj_map = USE_TO_UTFT8 ?
      subj_chain.map { |subj| subj.to_utf8[/CN=(.+ - )?([^,]+)/,2] } :
      subj_chain.map { |subj| subj.to_s(OpenSSL::X509::Name::RFC2253)[/CN=(.+ - )?([^,]+)/,2] }

    @server&.stop true

    assert_equal ['test.puma.localhost', 'intermediate.puma.localhost', 'ca.puma.localhost'], subj_map
  end

  def test_single_cert_file_with_ca
    cert_chain { |mini_ctx|
      mini_ctx.cert = "#{CHAIN_DIR}/cert.crt"
      mini_ctx.ca   = "#{CHAIN_DIR}/ca_chain.pem"
    }
  end

  def test_chain_cert_file_without_ca
    cert_chain { |mini_ctx| mini_ctx.cert = "#{CHAIN_DIR}/cert_chain.pem" }
  end

  def test_single_cert_string_with_ca
    cert_chain { |mini_ctx|
      mini_ctx.cert_pem = File.read "#{CHAIN_DIR}/cert.crt"
      mini_ctx.ca   = "#{CHAIN_DIR}/ca_chain.pem"
    }
  end

  def test_chain_cert_string_without_ca
    cert_chain { |mini_ctx| mini_ctx.cert_pem = File.read "#{CHAIN_DIR}/cert_chain.pem" }
  end
end if ::Puma::HAS_SSL && !::Puma::IS_JRUBY
