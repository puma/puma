require_relative "helper"

require "puma/binder"
require "puma/puma_http11"

class TestBinder < Minitest::Test
  def setup
    @events = Puma::Events.null
    @binder = Puma::Binder.new(@events)
  end

  def test_localhost_addresses_dont_alter_listeners_for_tcp_addresses
    skip_on :jruby

    @binder.parse(["tcp://localhost:10001"], @events)

    assert_equal [], @binder.listeners
  end

  def test_localhost_addresses_dont_alter_listeners_for_ssl_addresses
    skip_on :jruby

    key =  File.expand_path "../../examples/puma/puma_keypair.pem", __FILE__
    cert = File.expand_path "../../examples/puma/cert_puma.pem", __FILE__

    @binder.parse(["ssl://localhost:10002?key=#{key}&cert=#{cert}"], @events)

    assert_equal [], @binder.listeners
  end

  def test_binder_parses_ssl_cipher_filter
    skip_on :jruby

    key =  File.expand_path "../../examples/puma/puma_keypair.pem", __FILE__
    cert = File.expand_path "../../examples/puma/cert_puma.pem", __FILE__
    ssl_cipher_filter = "AES@STRENGTH"

    @binder.parse(["ssl://0.0.0.0?key=#{key}&cert=#{cert}&ssl_cipher_filter=#{ssl_cipher_filter}"], @events)

    ssl = @binder.instance_variable_get(:@ios)[0]
    ctx = ssl.instance_variable_get(:@ctx)
    assert_equal(ssl_cipher_filter, ctx.ssl_cipher_filter)
  end

  def test_binder_parses_jruby_ssl_options
    skip_unless :jruby

    keystore = File.expand_path "../../examples/puma/keystore.jks", __FILE__
    ssl_cipher_list = "TLS_DHE_RSA_WITH_DES_CBC_SHA,TLS_DHE_RSA_WITH_3DES_EDE_CBC_SHA"
    @binder.parse(["ssl://0.0.0.0:8080?keystore=#{keystore}&keystore-pass=&ssl_cipher_list=#{ssl_cipher_list}"], @events)

    ssl= @binder.instance_variable_get(:@ios)[0]
    ctx = ssl.instance_variable_get(:@ctx)
    assert_equal(keystore, ctx.keystore)
    assert_equal(ssl_cipher_list, ctx.ssl_cipher_list)
  end
end
