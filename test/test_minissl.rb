require_relative "helper"

require "puma/minissl" if ::Puma::HAS_SSL

class TestMiniSSL < Minitest::Test

  if Puma.jruby?
    def test_raises_with_invalid_keystore_file
      ctx = Puma::MiniSSL::Context.new

      exception = assert_raises(ArgumentError) { ctx.keystore = "/no/such/keystore" }
      assert_equal("No such keystore file '/no/such/keystore'", exception.message)
    end
  else
    def test_raises_with_invalid_key_file
      ctx = Puma::MiniSSL::Context.new

      exception = assert_raises(ArgumentError) { ctx.key = "/no/such/key" }
      assert_equal("No such key file '/no/such/key'", exception.message)
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
      assert_equal("No such cert file '/no/such/cert'", exception.message)
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
  end
end if ::Puma::HAS_SSL
