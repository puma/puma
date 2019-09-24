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
    binder.bindings[0].server.instance_variable_get(:@ctx)
  end
end

class TestBinder < TestBinderBase
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
    @binder.parse(["ssl://localhost:0?key=#{key}&cert=#{cert}"], @events)

    stdout = @events.stdout.string
    m = %r!ssl://127.0.0.1:(\d+)!.match(stdout)
    port = m[1].to_i

    refute_equal 0, port
    assert_match %r!ssl://127.0.0.1:(\d+)!, stdout
    if @binder.loopback_addresses.include?("::1")
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

    refute_includes @binder.bindings.map { |b| b.instance_variable_get(:@path) }, unix_path

    @binder.close_unix_paths

    assert File.exist?(unix_path)
  ensure
    if UNIX_SKT_EXIST
      File.unlink unix_path if File.exist? unix_path
    end
  end

  def test_binder_for_env
    @binder.parse(["tcp://localhost:#{UniquePort.call}"], @events)
    server = @binder.bindings.first.server

    proto = Puma::Binder::PROTO_ENV
    env = @binder.env_for_server(server)

    assert_equal(env, env.merge(proto)) # Env contains the entire PROTO_ENV
    assert_equal @events.stderr, env["rack.errors"]
  end

  def test_binder_for_env_unix
    skip UNIX_SKT_MSG unless UNIX_SKT_EXIST
    @binder.parse(["unix://test/#{name}_server.sock"], @events)
    server = @binder.bindings.first.server

    assert_equal("127.0.0.1", @binder.env_for_server(server)[Puma::Const::REMOTE_ADDR])
  ensure
    @binder.close_unix_paths if UNIX_SKT_EXIST
  end

  def test_binder_for_env_ssl
    @binder.parse(["ssl://localhost:0?key=#{key}&cert=#{cert}"], @events)
    server = @binder.bindings.first.server

    assert_equal(Puma::Const::HTTPS, @binder.env_for_server(server)[Puma::Const::HTTPS_KEY])
  end

  private

  def assert_parsing_logs_uri(order = [:unix, :tcp])
    skip UNIX_SKT_MSG if order.include?(:unix) && !UNIX_SKT_EXIST

    prepared_paths = {
        ssl: "ssl://127.0.0.1:#{UniquePort.call}?key=#{key}&cert=#{cert}",
        tcp: "tcp://127.0.0.1:#{UniquePort.call}",
        unix: "unix://test/#{name}_server.sock"
      }

    tested_paths = [prepared_paths[order[0]], prepared_paths[order[1]]]

    @binder.parse(tested_paths, @events)
    stdout = @events.stdout.string

    order.each do |prot|
      assert_match Regexp.new(prot.to_s), stdout
    end
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
