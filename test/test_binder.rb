# frozen_string_literal: true

require_relative "helper"

require "puma/binder"
require "puma/puma_http11"

class TestBinderBase < Minitest::Test
  def setup
    @events = Puma::Events.null
    @binder = Puma::Binder.new(@events)
    @key    = File.expand_path "../../examples/puma/puma_keypair.pem", __FILE__
    @cert   = File.expand_path "../../examples/puma/cert_puma.pem", __FILE__
  end

  private

  def ssl_context_for_binder(binder)
    binder.instance_variable_get(:@ios)[0].instance_variable_get(:@ctx)
  end
end

class TestBinder < TestBinderBase
  def test_localhost_addresses_dont_alter_listeners_for_tcp_addresses
    @binder.parse(["tcp://localhost:10001"], @events)

    assert_equal [], @binder.instance_variable_get(:@listeners)
  end
end

class TestBinderJRuby < TestBinderBase
  def setup
    super
    skip_unless :jruby
  end

  def test_binder_parses_jruby_ssl_options
    keystore = File.expand_path "../../examples/puma/keystore.jks", __FILE__
    ssl_cipher_list = "TLS_DHE_RSA_WITH_DES_CBC_SHA,TLS_DHE_RSA_WITH_3DES_EDE_CBC_SHA"

    @binder.parse(["ssl://0.0.0.0:8080?keystore=#{keystore}&keystore-pass=&ssl_cipher_list=#{ssl_cipher_list}"], @events)

    assert_equal keystore, ssl_context_for_binder(@binder).keystore
    assert_equal ssl_cipher_list, ssl_context_for_binder(@binder).ssl_cipher_list
  end
end

class TestBinderMRI < TestBinderBase
  def setup
    super
    skip_on :jruby
  end

  def test_localhost_addresses_dont_alter_listeners_for_ssl_addresses
    @binder.parse(["ssl://localhost:10002?key=#{@key}&cert=#{@cert}"], @events)

    assert_equal [], @binder.instance_variable_get(:@listeners)
  end

  def test_binder_parses_ssl_cipher_filter
    ssl_cipher_filter = "AES@STRENGTH"

    @binder.parse(["ssl://0.0.0.0?key=#{@key}&cert=#{@cert}&ssl_cipher_filter=#{ssl_cipher_filter}"], @events)

    assert_equal ssl_cipher_filter, ssl_context_for_binder(@binder).ssl_cipher_filter
  end

  def test_binder_parses_tlsv1_disabled
    @binder.parse(["ssl://0.0.0.0?key=#{@key}&cert=#{@cert}&no_tlsv1=true"], @events)

    assert ssl_context_for_binder(@binder).no_tlsv1
  end

  def test_binder_parses_tlsv1_enabled
    @binder.parse(["ssl://0.0.0.0?key=#{@key}&cert=#{@cert}&no_tlsv1=false"], @events)

    refute ssl_context_for_binder(@binder).no_tlsv1
  end

  def test_binder_parses_tlsv1_tlsv1_1_unspecified_defaults_to_enabled
    @binder.parse(["ssl://0.0.0.0?key=#{@key}&cert=#{@cert}"], @events)

    refute ssl_context_for_binder(@binder).no_tlsv1
    refute ssl_context_for_binder(@binder).no_tlsv1_1
  end

  def test_binder_parses_tlsv1_1_disabled
    @binder.parse(["ssl://0.0.0.0?key=#{@key}&cert=#{@cert}&no_tlsv1_1=true"], @events)

    assert ssl_context_for_binder(@binder).no_tlsv1_1
  end

  def test_binder_parses_tlsv1_1_enabled
    @binder.parse(["ssl://0.0.0.0?key=#{@key}&cert=#{@cert}&no_tlsv1_1=false"], @events)

    refute ssl_context_for_binder(@binder).no_tlsv1_1
  end
end
