require_relative "helper"

require "puma/minissl" if ::Puma::HAS_SSL

class TestMiniSSL < PumaTest

  if Puma.jruby?
    def test_raises_with_invalid_keystore_file
      ctx = Puma::MiniSSL::Context.new

      exception = assert_raises(ArgumentError) { ctx.keystore = "/no/such/keystore" }
      assert_equal("Keystore file '/no/such/keystore' does not exist", exception.message)
    end

    def test_raises_with_unreadable_keystore_file
      ctx = Puma::MiniSSL::Context.new

      File.stub(:exist?, true) do
        File.stub(:readable?, false) do
          exception = assert_raises(ArgumentError) { ctx.keystore = "/unreadable/keystore" }
          assert_equal("Keystore file '/unreadable/keystore' is not readable", exception.message)
        end
      end
    end
  else
    def test_raises_with_invalid_key_file
      ctx = Puma::MiniSSL::Context.new

      exception = assert_raises(ArgumentError) { ctx.key = "/no/such/key" }
      assert_equal("Key file '/no/such/key' does not exist", exception.message)
    end

    def test_raises_with_unreadable_key_file
      ctx = Puma::MiniSSL::Context.new

      File.stub(:exist?, true) do
        File.stub(:readable?, false) do
          exception = assert_raises(ArgumentError) { ctx.key = "/unreadable/key" }
          assert_equal("Key file '/unreadable/key' is not readable", exception.message)
        end
      end
    end

    def test_raises_with_invalid_cert_file
      ctx = Puma::MiniSSL::Context.new

      exception = assert_raises(ArgumentError) { ctx.cert = "/no/such/cert" }
      assert_equal("Cert file '/no/such/cert' does not exist", exception.message)
    end

    def test_raises_with_unreadable_cert_file
      ctx = Puma::MiniSSL::Context.new

      File.stub(:exist?, true) do
        File.stub(:readable?, false) do
          exception = assert_raises(ArgumentError) { ctx.key = "/unreadable/cert" }
          assert_equal("Key file '/unreadable/cert' is not readable", exception.message)
        end
      end
    end

    def test_raises_with_invalid_key_pem
      ctx = Puma::MiniSSL::Context.new

      exception = assert_raises(ArgumentError) { ctx.key_pem = nil }
      assert_equal("'key_pem' is not a String", exception.message)
    end

    # Regression test for https://github.com/puma/puma/issues/4082
    # A key_pem that does not match cert_pem must not be echoed back in the
    # error message, only the name of the offending parameter.
    def test_raises_with_mismatched_key_pem_without_leaking_its_contents
      _, cert_pem = self_signed_cert_pem
      other_key_pem = OpenSSL::PKey::RSA.new(2048).to_pem

      ctx = Puma::MiniSSL::Context.new
      ctx.cert_pem = cert_pem
      ctx.key_pem = other_key_pem

      # `MiniSSL::Server#initialize` builds its engine context the same way.
      exception = assert_raises(Puma::MiniSSL::SSLError) do
        Puma::MiniSSL::SSLContext.new ctx
      end

      assert_includes exception.message, "SSL_CTX_use_PrivateKey"
      assert_includes exception.message, "key_pem"
      refute_includes exception.message, "PRIVATE KEY"
      refute_includes exception.message, other_key_pem.lines[1].chomp
    end

    def test_raises_with_unreadable_ca_file
      ctx = Puma::MiniSSL::Context.new

      File.stub(:exist?, true) do
        File.stub(:readable?, false) do
          exception = assert_raises(ArgumentError) { ctx.ca = "/unreadable/cert" }
          assert_equal("ca file '/unreadable/cert' is not readable", exception.message)
        end
      end
    end

    def test_raises_with_invalid_cert_pem
      ctx = Puma::MiniSSL::Context.new

      exception = assert_raises(ArgumentError) { ctx.cert_pem = nil }
      assert_equal("'cert_pem' is not a String", exception.message)
    end

    def test_raises_with_invalid_key_password_command
      ctx = Puma::MiniSSL::Context.new
      ctx.key_password_command = '/unreadable/decrypt_command'

      assert_raises(Errno::ENOENT) { ctx.key_password }
    end

    def self_signed_cert_pem
      key = OpenSSL::PKey::RSA.new 2048
      cert = OpenSSL::X509::Certificate.new
      cert.version = 2
      cert.serial = 1
      cert.subject = cert.issuer = OpenSSL::X509::Name.parse "/CN=localhost"
      cert.public_key = key.public_key
      cert.not_before = Time.now
      cert.not_after = Time.now + 3600
      cert.sign key, OpenSSL::Digest::SHA256.new
      [key, cert.to_pem]
    end
  end
end if ::Puma::HAS_SSL
