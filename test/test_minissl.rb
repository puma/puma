require 'test/unit'
require 'puma'
require 'puma/minissl'

class TestMiniSSL < Test::Unit::TestCase

  if defined?(JRUBY_VERSION)
    def test_raises_with_invalid_keystore_file
      ctx = Puma::MiniSSL::Context.new

      exception = assert_raise(ArgumentError) { ctx.keystore = "/no/such/keystore" }
      assert_equal("No such keystore file '/no/such/keystore'", exception.message)
    end
  else
    def test_raises_with_invalid_key_file
      ctx = Puma::MiniSSL::Context.new

      exception = assert_raise(ArgumentError) { ctx.key = "/no/such/key" }
      assert_equal("No such key file '/no/such/key'", exception.message)
    end

    def test_raises_with_invalid_cert_file
      ctx = Puma::MiniSSL::Context.new

      exception = assert_raise(ArgumentError) { ctx.cert = "/no/such/cert" }
      assert_equal("No such cert file '/no/such/cert'", exception.message)
    end
  end
end
