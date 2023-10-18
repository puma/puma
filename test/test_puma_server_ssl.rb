# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/test_puma/server_in_process"

if ::Puma::HAS_SSL
  require "puma/minissl"

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

class TestPumaServerSSL < TestPuma::ServerInProcess
  parallelize_me!

  def setup
    set_bind_type :ssl
  end

  def test_url_scheme_for_https
    server_run
    assert_equal "https", send_http_read_resp_body
  end

  def test_request_wont_block_thread
    server_run

    # Open a connection and give enough data to trigger a read, then wait
    socket = send_http 'HEAD'
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
    server_run
    giant = "x" * 2056610

    server_run app: ->(_) { [200, {}, [giant]] }

    body = send_http_read_resp_body

    assert_equal giant.bytesize, body.bytesize
  end

  def test_form_submit
    server_run app: ->(env) do
      [200, {}, [env['rack.url_scheme'], "\n", env['rack.input'].read]]
    end

    req = "POST / HTTP/1.1\r\nContent-Type: text/plain\r\nContent-Length: 7\r\n\r\na=1&b=2"

    body = send_http_read_resp_body req

    assert_equal "https\na=1&b=2", body
  end

  def rejection(server, min_max, ssl_version)
    if server
      server_run ctx: server
    else
      server_run
    end

    msg = nil

    assert_raises(OpenSSL::SSL::SSLError) do
      begin
        send_http_read_response ctx: new_ctx { |ctx|
          if PROTOCOL_USE_MIN_MAX && min_max
            ctx.max_version = min_max
          else
            ctx.ssl_version = ssl_version
          end
        }
      rescue => e
        msg = e.message
        raise e
      end
    end

    unless Puma::IS_JRUBY
      expected = /SSL_connect SYSCALL returned=5|wrong version number|(unknown|unsupported) protocol|no protocols available|version too low|unknown SSL method/
      assert_match expected, msg
    end

    # make sure a good request succeeds
    assert_equal "https", send_http_read_resp_body(GET_10)
  end

  def test_ssl_v3_rejection
    skip("SSLv3 protocol is unavailable") if Puma::MiniSSL::OPENSSL_NO_SSL3

    rejection nil, nil, :SSLv3
  end

  def test_tls_v1_rejection
    rejection ->(ctx) { ctx.no_tlsv1 = true }, :TLS1, :TLSv1
  end

  def test_tls_v1_1_rejection
    rejection ->(ctx) { ctx.no_tlsv1_1 = true }, :TLS1_1, :TLSv1_1
  end

  def test_tls_v1_3
    skip("TLSv1.3 protocol is not available") unless OpenSSL::SSL.const_defined? :TLS1_3_VERSION

    if Puma::IS_JRUBY
      server_run ctx: ->(ctx) { ctx.protocols = %w[TLSv1 TLSv1.1 TLSv1.2 TLSv1.3] }
    else
      server_run
    end

    socket = send_http ctx: new_ctx { |c|
      if PROTOCOL_USE_MIN_MAX
        c.min_version = :TLS1_3
      else
        c.ssl_version = :TLSv1_3
      end
    }

    body = socket.read_body

    assert_equal "TLSv1.3", socket.ssl_version
    assert_equal "https", body
  end

  def test_http_rejection
    body_http  = nil
    body_https = nil

    server_run

    tcp = Thread.new do
      assert_raises(Errno::ECONNREFUSED, EOFError, Timeout::Error) do
        socket = new_socket(bind_type: :tcp) << GET_11
        socket.read_body timeout: 4
      end
    end

    ssl = Thread.new do
      body_https = send_http_read_resp_body
    end

    tcp.join
    ssl.join
    sleep 1.0

    assert_nil body_http
    assert_equal "https", body_https

    thread_pool = @server.instance_variable_get(:@thread_pool)
    busy_threads = thread_pool.spawned - thread_pool.waiting

    assert busy_threads.zero?, "Our http connection wasn't dropped"
  end

  def verify_client_cert_roundtrip(tls1_2 = nil)
    app = ->(env) { [200, {}, [env['puma.peercert'].to_s]] }

    ctx = Puma::MiniSSL::Context.new
    if ::Puma::IS_JRUBY
      ctx.keystore = "#{CLIENT_CERTS_PATH}/keystore.jks"
      ctx.keystore_pass = "jruby_puma"
    else
      ctx.cert = "#{CLIENT_CERTS_PATH}/server.crt"
      ctx.key  = "#{CLIENT_CERTS_PATH}/server.key"
      ctx.ca   = "#{CLIENT_CERTS_PATH}/ca.crt"
    end
    ctx.verify_mode = MINI_FORCE_PEER

    server_run app: app, ctx: ctx

    client_cert = File.read "#{CLIENT_CERTS_PATH}/client.crt"

    socket = send_http ctx: new_ctx { |c|
      ca   = "#{CLIENT_CERTS_PATH}/ca.crt"
      key  = "#{CLIENT_CERTS_PATH}/client.key"
      c.ca_file = ca
      c.cert = ::OpenSSL::X509::Certificate.new client_cert
      c.key  = ::OpenSSL::PKey::RSA.new File.read(key)
      c.verify_mode = ::OpenSSL::SSL::VERIFY_PEER
      if tls1_2
        if c.respond_to? :max_version=
          c.max_version = :TLS1_2
        else
          c.ssl_version = :TLSv1_2
        end
      end
    }

    assert_equal client_cert, socket.read_body
    socket
  end

  def test_verify_client_cert_roundtrip_tls1_2
    socket = verify_client_cert_roundtrip(true)
    assert_equal "TLSv1.2", socket.ssl_version
  end

  # should use TLSv1.3 with OpenSSL 1.1 or later
  def test_verify_client_cert_roundtrip_tls1_3
    skip("TLSv1.3 protocol is not available") unless HAS_TLS_1_3
    socket = verify_client_cert_roundtrip
    assert_equal "TLSv1.3", socket.ssl_version
  end

  def test_verify_client_cert_roundtrip_with_curl_client
    skip_if :windows

    app = ->(env) { [200, {}, [env['puma.peercert'].to_s]] }

    ctx = Puma::MiniSSL::Context.new
    if ::Puma::IS_JRUBY
      ctx.keystore = "#{CLIENT_CERTS_PATH}/keystore.jks"
      ctx.keystore_pass = "jruby_puma"
    else
      ctx.cert = "#{CLIENT_CERTS_PATH}/server.crt"
      ctx.key  = "#{CLIENT_CERTS_PATH}/server.key"
      ctx.ca   = "#{CLIENT_CERTS_PATH}/ca.crt"
    end
    ctx.verify_mode = MINI_FORCE_PEER

    server_run app: app, ctx: ctx

    ca   = "#{CLIENT_CERTS_PATH}/ca.crt"
    cert = "#{CLIENT_CERTS_PATH}/client.crt"
    key  = "#{CLIENT_CERTS_PATH}/client.key"
    # NOTE: JRuby used to end up in a hang with TLS peer verification enabled
    # it's easier to reproduce using an external client such as CURL (using net/http client the bug isn't triggered)
    # also the "hang", being buffering related, seems to showcase better with TLS 1.2 than 1.3
    body = curl_and_get_response "https://#{LOCALHOST}:#{bind_port}",
      args: "--cacert #{ca} --cert #{cert} --key #{key} --tlsv1.2 --tls-max 1.2"

    client_cert = File.read "#{CLIENT_CERTS_PATH}/client.crt"

    assert_equal client_cert, body
  end

  unless Puma::IS_JRUBY

    def test_verify_client_cert_roundtrip_pems
      app = ->(env) { [200, {}, [env['puma.peercert'].to_s]] }

      ctx = Puma::MiniSSL::Context.new
      ctx.cert_pem = File.read "#{CLIENT_CERTS_PATH}/server.crt"
      ctx.key_pem  = File.read "#{CLIENT_CERTS_PATH}/server.key"
      ctx.ca   = "#{CLIENT_CERTS_PATH}/ca.crt"
      ctx.verify_mode = MINI_FORCE_PEER

      server_run app: app, ctx: ctx

      client_cert = File.read "#{CLIENT_CERTS_PATH}/client.crt"

      socket = send_http ctx: new_ctx { |c|
        ca   = "#{CLIENT_CERTS_PATH}/ca.crt"
        key  = "#{CLIENT_CERTS_PATH}/client.key"
        c.ca_file = ca
        c.cert = ::OpenSSL::X509::Certificate.new client_cert
        c.key  = ::OpenSSL::PKey::RSA.new File.read(key)
        c.verify_mode = ::OpenSSL::SSL::VERIFY_PEER
      }

      assert_equal client_cert, socket.read_body
    end

    def test_with_encrypted_key
      key_command = ::Puma::IS_WINDOWS ? "echo hello world" :
        "#{CERT_PATH}/key_password_command.sh"

      ctx = Puma::MiniSSL::Context.new
      ctx.cert = "#{CERT_PATH}/cert_puma.pem"
      ctx.key  = "#{CERT_PATH}/encrypted_puma_keypair.pem"
      ctx.verify_mode = MINI_VERIFY_NONE
      ctx.key_password_command = key_command

      server_run ctx: ctx

      assert_equal "https", send_http_read_resp_body
    end

    def test_with_encrypted_pem
      key_command = ::Puma::IS_WINDOWS ? "echo hello world" :
        "#{CERT_PATH}/key_password_command.sh"

      ctx = Puma::MiniSSL::Context.new
      ctx.cert_pem = File.read "#{CERT_PATH}/cert_puma.pem"
      ctx.key_pem  = File.read "#{CERT_PATH}/encrypted_puma_keypair.pem"
      ctx.verify_mode = MINI_VERIFY_NONE
      ctx.key_password_command = key_command

      server_run ctx: ctx

      assert_equal "https", send_http_read_resp_body
    end

    def test_invalid_cert
      assert_raises(Puma::MiniSSL::SSLError) do
        server_run ctx: ->(ctx) { ctx.cert = __FILE__ }
      end
    end

    def test_invalid_key
      assert_raises(Puma::MiniSSL::SSLError) do
        server_run ctx: ->(ctx) { ctx.key = __FILE__ }
      end
    end

    def test_invalid_cert_pem
      assert_raises(Puma::MiniSSL::SSLError) do
        server_run ctx: ->(ctx) {
          ctx.instance_variable_set(:@cert, nil)
          ctx.cert_pem = 'Not a valid pem'
        }
      end
    end

    def test_invalid_key_pem
      assert_raises(Puma::MiniSSL::SSLError) do
        server_run ctx: ->(ctx) {
          ctx.instance_variable_set(:@key, nil)
          ctx.key_pem = 'Not a valid pem'
        }
      end
    end

    def test_invalid_ca
      assert_raises(Puma::MiniSSL::SSLError) do
        server_run ctx: ->(ctx) {
          ctx.ca = __FILE__
        }
      end
    end
  end
end if ::Puma::HAS_SSL

# client-side TLS authentication tests
class TestPumaServerSSLClient < TestPuma::ServerInProcess
  parallelize_me!

  CERT_PATH = File.expand_path "../examples/puma/client-certs", __dir__

  def setup
    set_bind_type :ssl
  end

  def new_server_context
    ctx = Puma::MiniSSL::Context.new
    if Puma::IS_JRUBY
      ctx.keystore =  "#{CERT_PATH}/keystore.jks"
      ctx.keystore_pass = 'jruby_puma'
    else
      ctx.key  = "#{CERT_PATH}/server.key"
      ctx.cert = "#{CERT_PATH}/server.crt"
      ctx.ca   = "#{CERT_PATH}/ca.crt"
    end
    ctx.verify_mode = MINI_FORCE_PEER
    ctx
  end

  def assert_ssl_client_error_match(error, subject: nil, context: new_server_context, &blk)
    log_writer = SSLLogWriterHelper.new StringIO.new, StringIO.new

    server_run log_writer: log_writer, ctx: context

    host_addrs = @server.binder.ios.map { |io| io.to_io.addr[2] }

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
    @server&.stop true
  end

  def test_verify_fail_if_no_client_cert
    error = Puma::IS_JRUBY ? /Empty client certificate chain/ : 'peer did not return a certificate'
    assert_ssl_client_error_match(error) do |client_ctx|
      # nothing
    end
  end

  def test_verify_fail_if_client_unknown_ca
    error = Puma::IS_JRUBY ? /No trusted certificate found/ : /self[- ]signed certificate in certificate chain/
    cert_subject = Puma::IS_JRUBY ? '/DC=net/DC=puma/CN=localhost' : '/DC=net/DC=puma/CN=CAU'
    assert_ssl_client_error_match(error, subject: cert_subject) do |client_ctx|
      key = "#{CERT_PATH}/client_unknown.key"
      crt = "#{CERT_PATH}/client_unknown.crt"
      client_ctx.key = OpenSSL::PKey::RSA.new File.read(key)
      client_ctx.cert = OpenSSL::X509::Certificate.new File.read(crt)
      client_ctx.ca_file = "#{CERT_PATH}/unknown_ca.crt"
    end

  end

  def test_verify_fail_if_client_expired_cert
    error = Puma::IS_JRUBY ? /NotAfter:/ : 'certificate has expired'
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
    ctx.verify_mode = MINI_VERIFY_PEER

    assert_ssl_client_error_match(false, context: ctx) do |client_ctx|
      key = "#{CERT_PATH}/client.key"
      crt = "#{CERT_PATH}/client.crt"
      client_ctx.key = OpenSSL::PKey::RSA.new File.read(key)
      client_ctx.cert = OpenSSL::X509::Certificate.new File.read(crt)
      client_ctx.ca_file = "#{CERT_PATH}/ca.crt"
      client_ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
    end
  end if Puma::IS_JRUBY

  def test_verify_client_cert_without_truststore
    ctx = Puma::MiniSSL::Context.new
    ctx.keystore = "#{CERT_PATH}/server.p12"
    ctx.keystore_type = 'pkcs12'
    ctx.keystore_pass = 'jruby_puma'
    ctx.truststore = "#{CERT_PATH}/unknown_ca_store.p12"
    ctx.truststore_type = 'pkcs12'
    ctx.truststore_pass = 'jruby_puma'
    ctx.verify_mode = MINI_VERIFY_PEER

    assert_ssl_client_error_match(true, context: ctx) do |client_ctx|
      key = "#{CERT_PATH}/client.key"
      crt = "#{CERT_PATH}/client.crt"
      client_ctx.key = OpenSSL::PKey::RSA.new File.read(key)
      client_ctx.cert = OpenSSL::X509::Certificate.new File.read(crt)
      client_ctx.ca_file = "#{CERT_PATH}/ca.crt"
      client_ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
    end
  end if Puma::IS_JRUBY

  def test_allows_using_default_truststore
    ctx = Puma::MiniSSL::Context.new
    ctx.keystore = "#{CERT_PATH}/server.p12"
    ctx.keystore_type = 'pkcs12'
    ctx.keystore_pass = 'jruby_puma'
    ctx.truststore = :default
    # NOTE: a little hard to test - we're at least asserting that setting :default does not raise errors
    ctx.verify_mode = MINI_VERIFY_NONE

    assert_ssl_client_error_match(false, context: ctx) do |client_ctx|
      key = "#{CERT_PATH}/client.key"
      crt = "#{CERT_PATH}/client.crt"
      client_ctx.key = OpenSSL::PKey::RSA.new File.read(key)
      client_ctx.cert = OpenSSL::X509::Certificate.new File.read(crt)
      client_ctx.ca_file = "#{CERT_PATH}/ca.crt"
      client_ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
    end
  end if Puma::IS_JRUBY

  def test_allows_to_specify_cipher_suites_and_protocols
    ctx = new_server_context
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
  end if Puma::IS_JRUBY

  def test_fails_when_no_cipher_suites_in_common
    ctx = new_server_context
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
  end if Puma::IS_JRUBY

  def test_verify_client_cert_with_truststore_without_pass
    ctx = Puma::MiniSSL::Context.new
    ctx.keystore = "#{CERT_PATH}/server.p12"
    ctx.keystore_type = 'pkcs12'
    ctx.keystore_pass = 'jruby_puma'
    ctx.truststore =  "#{CERT_PATH}/ca_store.jks" # cert entry can be read without password
    ctx.truststore_type = 'jks'
    ctx.verify_mode = MINI_VERIFY_PEER

    assert_ssl_client_error_match(false, context: ctx) do |client_ctx|
      key = "#{CERT_PATH}/client.key"
      crt = "#{CERT_PATH}/client.crt"
      client_ctx.key = OpenSSL::PKey::RSA.new File.read(key)
      client_ctx.cert = OpenSSL::X509::Certificate.new File.read(crt)
      client_ctx.ca_file = "#{CERT_PATH}/ca.crt"
      client_ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
    end
  end if Puma::IS_JRUBY

end if ::Puma::HAS_SSL

class TestPumaServerSSLWithCertPemAndKeyPem < TestPuma::ServerInProcess
  CERT_PATH = File.expand_path "../examples/puma/client-certs", __dir__

  def setup
    set_bind_type :ssl
  end

  def test_server_ssl_with_cert_pem_and_key_pem
    server_run app: ->(_) { [200, {}, [env['rack.url_scheme']]] },
      ctx: ->(ctx) {
        ctx.cert_pem = File.read "#{CERT_PATH}/server.crt"
        ctx.key_pem  = File.read "#{CERT_PATH}/server.key"
      }

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
    @server&.stop true
  end
end if ::Puma::HAS_SSL && !Puma::IS_JRUBY

#
# Test certificate chain support, The certs and the whole certificate chain for
# this tests are located in ../examples/puma/chain_cert and were generated with
# the following commands:
#
#   bundle exec ruby ../examples/puma/chain_cert/generate_chain_test.rb
#
class TestPumaSSLCertChain < TestPuma::ServerInProcess
  CHAIN_DIR = File.expand_path '../examples/puma/chain_cert', __dir__

  # OpenSSL::X509::Name#to_utf8 only available in Ruby 2.5 and later
  USE_TO_UTFT8 = OpenSSL::X509::Name.instance_methods(false).include? :to_utf8

  def setup
    set_bind_type :ssl
  end

  def cert_chain(&blk)
    server_run ctx: blk

    socket = send_http host: LOCALHOST

    assert_equal 'https', socket.read_body

    subj_chain = socket.peer_cert_chain.map(&:subject)
    subj_map = USE_TO_UTFT8 ?
      subj_chain.map { |subj| subj.to_utf8[/CN=(.+ - )?([^,]+)/,2] } :
      subj_chain.map { |subj| subj.to_s(OpenSSL::X509::Name::RFC2253)[/CN=(.+ - )?([^,]+)/,2] }

    assert_equal ['test.puma.localhost', 'intermediate.puma.localhost', 'ca.puma.localhost'], subj_map
  end

  def test_single_cert_file_with_ca
    cert_chain { |mini_ctx|
      mini_ctx.key  = "#{CHAIN_DIR}/cert.key"
      mini_ctx.cert = "#{CHAIN_DIR}/cert.crt"
      mini_ctx.ca   = "#{CHAIN_DIR}/ca_chain.pem"
    }
  end

  def test_chain_cert_file_without_ca
    cert_chain { |mini_ctx|
      mini_ctx.key  = "#{CHAIN_DIR}/cert.key"
      mini_ctx.cert = "#{CHAIN_DIR}/cert_chain.pem"
    }
  end

  def test_single_cert_string_with_ca
    cert_chain { |mini_ctx|
      mini_ctx.key  = "#{CHAIN_DIR}/cert.key"
      mini_ctx.cert_pem = File.read "#{CHAIN_DIR}/cert.crt"
      mini_ctx.ca   = "#{CHAIN_DIR}/ca_chain.pem"
    }
  end

  def test_chain_cert_string_without_ca
    cert_chain { |mini_ctx|
      mini_ctx.key  = "#{CHAIN_DIR}/cert.key"
      mini_ctx.cert_pem = File.read "#{CHAIN_DIR}/cert_chain.pem"
    }
  end
end if ::Puma::HAS_SSL && !::Puma::IS_JRUBY
