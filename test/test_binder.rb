# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/ssl"

require "puma/binder"
require "puma/puma_http11"

class TestBinderBase < Minitest::Test
  include SSLHelper

  def setup
    @events = Puma::Events.strings
    @binder = Puma::Binder.new(@events)
  end

  private

  def ssl_context_for_binder(binder = @binder)
    binder.ios[0].instance_variable_get(:@ctx)
  end
end

class TestBinder < TestBinderBase
  def test_localhost_addresses_dont_alter_listeners_for_tcp_addresses
    @binder.parse ["tcp://localhost:10001"], @events

    assert_equal [], @binder.instance_variable_get(:@listeners)
  end

  def test_localhost_addresses_dont_alter_listeners_for_ssl_addresses
    @binder.parse ["ssl://localhost:10002?#{ssl_query}"], @events

    assert_equal [], @binder.instance_variable_get(:@listeners)
  end

  def test_correct_zero_port
    @binder.parse ["tcp://localhost:0"], @events

    m = %r!tcp://127.0.0.1:(\d+)!.match(@events.stdout.string)
    port = m[1].to_i

    refute_equal 0, port
  end

  def test_logs_all_localhost_bindings
    @binder.parse ["tcp://localhost:0"], @events

    assert_match %r!tcp://127.0.0.1:(\d+)!, @events.stdout.string
    if @binder.loopback_addresses.include?("::1")
      assert_match %r!tcp://\[::1\]:(\d+)!, @events.stdout.string
    end
  end

  def test_correct_zero_port_ssl
    skip("Implement in 4.3")
    @binder.parse ["ssl://localhost:0?#{ssl_query}"], @events

    stdout = @events.stdout.string
    m = %r!tcp://127.0.0.1:(\d+)!.match(stdout)
    port = m[1].to_i

    refute_equal 0, port
    assert_match %r!ssl://127.0.0.1:(\d+)!, stdout
    if @binder.loopback_addresses.include? '::1'
      assert_match %r!ssl://\[::1\]:(\d+)!, stdout
    end
  end

  def test_allows_both_ssl_and_tcp
    assert_parsing_logs_uri [:ssl, :tcp]
  end

  def test_allows_both_unix_and_tcp
    assert_parsing_logs_uri [:unix, :tcp]
  end

  def test_allows_both_tcp_and_unix
    assert_parsing_logs_uri [:tcp, :unix]
  end

  def test_pre_existing_unix
    skip UNIX_SKT_MSG unless UNIX_SKT_EXIST
    unix_path = "test/#{name}_server.sock"

    File.open(unix_path, mode: 'wb') { |f| f.puts 'pre existing' }
    @binder.parse ["unix://#{unix_path}"], @events

    assert_match %r!unix://#{unix_path}!, @events.stdout.string

    refute_includes @binder.instance_variable_get(:@unix_paths), unix_path

    @binder.close_unix_paths

    assert File.exist?(unix_path)

  ensure
    if UNIX_SKT_EXIST
      File.unlink unix_path if File.exist? unix_path
    end
  end

  def test_binder_parses_tlsv1_disabled
    @binder.parse ["ssl://0.0.0.0:0?#{ssl_query}&no_tlsv1=true"], @events

    assert ssl_context_for_binder.no_tlsv1
  end

  def test_binder_parses_tlsv1_enabled
    @binder.parse ["ssl://0.0.0.0:0?#{ssl_query}&no_tlsv1=false"], @events

    refute ssl_context_for_binder.no_tlsv1
  end

  def test_binder_parses_tlsv1_tlsv1_1_unspecified_defaults_to_enabled
    @binder.parse ["ssl://0.0.0.0:0?#{ssl_query}"], @events

    refute ssl_context_for_binder.no_tlsv1
    refute ssl_context_for_binder.no_tlsv1_1
  end

  def test_binder_parses_tlsv1_1_disabled
    @binder.parse ["ssl://0.0.0.0:0?#{ssl_query}&no_tlsv1_1=true"], @events

    assert ssl_context_for_binder.no_tlsv1_1
  end

  def test_binder_parses_tlsv1_1_enabled
    @binder.parse ["ssl://0.0.0.0:0?#{ssl_query}&no_tlsv1_1=false"], @events

    refute ssl_context_for_binder.no_tlsv1_1
  end

  private

  def assert_parsing_logs_uri(order = [:unix, :tcp])
    skip UNIX_SKT_MSG if order.include?(:unix) && !UNIX_SKT_EXIST

    prepared_paths = {
        ssl: "ssl://127.0.0.1:#{UniquePort.call}?#{ssl_query}",
        tcp: "tcp://127.0.0.1:#{UniquePort.call}",
        unix: "unix://test/#{name}_server.sock"
      }

    tested_paths = [prepared_paths[order[0]], prepared_paths[order[1]]]

    @binder.parse tested_paths, @events
    stdout = @events.stdout.string

    assert stdout.include?(prepared_paths[order[0]]), "\n#{stdout}\n"
    assert stdout.include?(prepared_paths[order[1]]), "\n#{stdout}\n"
  ensure
    @binder.close_unix_paths if order.include?(:unix) && UNIX_SKT_EXIST
  end
end

class TestBinderJRuby < TestBinderBase
  def test_binder_parses_jruby_ssl_options
    keystore = File.expand_path "../../examples/puma/keystore.jks", __FILE__
    ssl_cipher_list = "TLS_DHE_RSA_WITH_DES_CBC_SHA,TLS_DHE_RSA_WITH_3DES_EDE_CBC_SHA"

    @binder.parse ["ssl://0.0.0.0:8080?#{ssl_query}"], @events

    assert_equal keystore, ssl_context_for_binder.keystore
    assert_equal ssl_cipher_list, ssl_context_for_binder.ssl_cipher_list
  end
end if ::Puma::IS_JRUBY

class TestBinderMRI < TestBinderBase
  def test_binder_parses_ssl_cipher_filter
    ssl_cipher_filter = "AES@STRENGTH"

    @binder.parse ["ssl://0.0.0.0?#{ssl_query}&ssl_cipher_filter=#{ssl_cipher_filter}"], @events

    assert_equal ssl_cipher_filter, ssl_context_for_binder.ssl_cipher_filter
  end
end unless ::Puma::IS_JRUBY
