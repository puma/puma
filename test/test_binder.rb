# frozen_string_literal: true

require_relative "helper"

require "puma/binder"
require "puma/puma_http11"

class TestBinderBase < Minitest::Test
  def setup
    @events = Puma::Events.strings
    @binder = Puma::Binder.new(@events)
  end

  private

  def key
    @key ||= File.expand_path "../../examples/puma/puma_keypair.pem", __FILE__
  end

  def cert
    @cert ||= File.expand_path "../../examples/puma/cert_puma.pem", __FILE__
  end

  def ssl_context_for_binder(binder)
    binder.instance_variable_get(:@ios)[0].instance_variable_get(:@ctx)
  end
end

class TestBinder < TestBinderBase
  def test_localhost_addresses_dont_alter_listeners_for_tcp_addresses
    @binder.parse(["tcp://localhost:10001"], @events)

    assert_equal [], @binder.instance_variable_get(:@listeners)
  end

  def test_correct_zero_port
    @binder.parse(["tcp://localhost:0"], @events)

    m = %r!tcp://127.0.0.1:(\d+)!.match(@events.stdout.string)
    port = m[1].to_i

    refute_equal 0, port
  end

  def test_logs_all_localhost_bindings
    @binder.parse(["tcp://localhost:0"], @events)

    assert_match %r!tcp://127.0.0.1:(\d+)!, @events.stdout.string
    if @binder.loopback_addresses.include?("::1")
      assert_match %r!tcp://\[::1\]:(\d+)!, @events.stdout.string
    end
  end

  def test_correct_zero_port_ssl
    skip("Implement in 4.3")
    @binder.parse(["ssl://localhost:0?key=#{key}&cert=#{cert}"], @events)

    stdout = @events.stdout.string
    m = %r!tcp://127.0.0.1:(\d+)!.match(stdout)
    port = m[1].to_i

    refute_equal 0, port
    assert_match %r!ssl://127.0.0.1:(\d+)!, stdout
    if @binder.loopback_addresses.include?("::1")
      assert_match %r!ssl://\[::1\]:(\d+)!, stdout
    end
  end

  def test_correct_doublebind
    @binder.parse(["ssl://localhost:0?key=#{key}&cert=#{cert}", "tcp://localhost:0"], @events)

    stdout = @events.stdout.string

    %w[tcp ssl].each do |prot|
      assert_match %r!#{prot}://127.0.0.1:(\d+)!, stdout
      if @binder.loopback_addresses.include?("::1")
        assert_match %r!#{prot}://\[::1\]:(\d+)!, stdout
      end
    end
  end

  def test_allows_both_unix_and_tcp
    assert_parsing_logs_uri [:unix, :tcp]
  end

  def test_allows_both_tcp_and_unix
    assert_parsing_logs_uri [:tcp, :unix]
  end

  private

  def assert_parsing_logs_uri(order = [:unix, :tcp])
    skip UNIX_SKT_MSG unless UNIX_SKT_EXIST

    path_unix = "test/#{name}_server.sock"
    uri_unix  = "unix://#{path_unix}"
    uri_tcp   = "tcp://127.0.0.1:#{UniquePort.call}"

    if order == [:unix, :tcp]
      @binder.parse([uri_tcp, uri_unix], @events)
    elsif order == [:tcp, :unix]
      @binder.parse([uri_unix, uri_tcp], @events)
    else
      raise ArgumentError
    end

    stdout = @events.stdout.string

    assert stdout.include?(uri_unix), "\n#{stdout}\n"
    assert stdout.include?(uri_tcp) , "\n#{stdout}\n"
  ensure
    @binder.close_unix_paths if UNIX_SKT_EXIST
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
    @binder.parse(["ssl://localhost:10002?key=#{key}&cert=#{cert}"], @events)

    assert_equal [], @binder.instance_variable_get(:@listeners)
  end

  def test_binder_parses_ssl_cipher_filter
    ssl_cipher_filter = "AES@STRENGTH"

    @binder.parse(["ssl://0.0.0.0?key=#{key}&cert=#{cert}&ssl_cipher_filter=#{ssl_cipher_filter}"], @events)

    assert_equal ssl_cipher_filter, ssl_context_for_binder(@binder).ssl_cipher_filter
  end

  def test_binder_parses_tlsv1_disabled
    @binder.parse(["ssl://0.0.0.0?key=#{key}&cert=#{cert}&no_tlsv1=true"], @events)

    assert ssl_context_for_binder(@binder).no_tlsv1
  end

  def test_binder_parses_tlsv1_enabled
    @binder.parse(["ssl://0.0.0.0?key=#{key}&cert=#{cert}&no_tlsv1=false"], @events)

    refute ssl_context_for_binder(@binder).no_tlsv1
  end

  def test_binder_parses_tlsv1_tlsv1_1_unspecified_defaults_to_enabled
    @binder.parse(["ssl://0.0.0.0?key=#{key}&cert=#{cert}"], @events)

    refute ssl_context_for_binder(@binder).no_tlsv1
    refute ssl_context_for_binder(@binder).no_tlsv1_1
  end

  def test_binder_parses_tlsv1_1_disabled
    @binder.parse(["ssl://0.0.0.0?key=#{key}&cert=#{cert}&no_tlsv1_1=true"], @events)

    assert ssl_context_for_binder(@binder).no_tlsv1_1
  end

  def test_binder_parses_tlsv1_1_enabled
    @binder.parse(["ssl://0.0.0.0?key=#{key}&cert=#{cert}&no_tlsv1_1=false"], @events)

    refute ssl_context_for_binder(@binder).no_tlsv1_1
  end
end
