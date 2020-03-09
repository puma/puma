# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/ssl"

require "puma/binder"
require "puma/puma_http11"
require "puma/events"

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
  parallelize_me!

  def test_localhost_addresses_dont_alter_listeners_for_tcp_addresses
    @binder.parse ["tcp://localhost:0"], @events

    assert_empty @binder.listeners
  end

  def test_home_alters_listeners_for_tcp_addresses
    port = UniquePort.call
    @binder.parse ["tcp://127.0.0.1:#{port}"], @events

    assert_equal "tcp://127.0.0.1:#{port}", @binder.listeners[0][0]
    assert_kind_of TCPServer, @binder.listeners[0][1]
  end

  def test_connected_ports
    ports = (1..3).map { |_| UniquePort.call }

    @binder.parse(ports.map { |p| "tcp://localhost:#{p}" }, @events)

    assert_equal ports, @binder.connected_ports
  end

  def test_localhost_addresses_dont_alter_listeners_for_ssl_addresses
    @binder.parse ["ssl://localhost:0?#{ssl_query}"], @events

    assert_empty @binder.listeners
  end

  def test_home_alters_listeners_for_ssl_addresses
    port = UniquePort.call
    @binder.parse ["ssl://127.0.0.1:#{port}?#{ssl_query}"], @events

    assert_equal "ssl://127.0.0.1:#{port}?#{ssl_query}", @binder.listeners[0][0]
    assert_kind_of TCPServer, @binder.listeners[0][1]
  end

  def test_correct_zero_port
    @binder.parse ["tcp://localhost:0"], @events

    m = %r!tcp://127.0.0.1:(\d+)!.match(@events.stdout.string)
    port = m[1].to_i

    refute_equal 0, port
  end

  def test_correct_zero_port_ssl
    skip("Implement later")
    ssl_regex = %r!ssl://127.0.0.1:(\d+)!

    @binder.parse ["ssl://localhost:0?#{ssl_query}"], @events

    port = ssl_regex.match(@events.stdout.string)[1].to_i

    refute_equal 0, port
  end

  def test_logs_all_localhost_bindings
    @binder.parse ["tcp://localhost:0"], @events

    assert_match %r!tcp://127.0.0.1:(\d+)!, @events.stdout.string
    if Socket.ip_address_list.any? {|i| i.ipv6_loopback? }
      assert_match %r!tcp://\[::1\]:(\d+)!, @events.stdout.string
    end
  end

  def test_logs_all_localhost_bindings_ssl
    skip("Incorrectly logs localhost, not 127.0.0.1")
    @binder.parse ["ssl://localhost:0?#{ssl_query}"], @events

    assert_match %r!ssl://127.0.0.1:(\d+)!, @events.stdout.string
    if Socket.ip_address_list.any? {|i| i.ipv6_loopback? }
      assert_match %r!ssl://\[::1\]:(\d+)!, @events.stdout.string
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

    refute_includes @binder.unix_paths, unix_path

    @binder.close_listeners

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

  def test_env_contains_protoenv
    @binder.parse ["ssl://localhost:0?#{ssl_query}"], @events

    env_hash = @binder.envs[@binder.ios.first]

    @binder.proto_env.each do |k,v|
      assert_equal env_hash[k], v
    end
  end

  def test_env_contains_stderr
    @binder.parse ["ssl://localhost:0?#{ssl_query}"], @events

    env_hash = @binder.envs[@binder.ios.first]

    assert_equal @events.stderr, env_hash["rack.errors"]
  end

  def test_close_calls_close_on_ios
    @mocked_ios = [Minitest::Mock.new, Minitest::Mock.new]
    @mocked_ios.each { |m| m.expect(:close, true) }
    @binder.ios = @mocked_ios

    @binder.close

    assert @mocked_ios.map(&:verify).all?
  end

  def test_redirects_for_restart_creates_a_hash
    @binder.parse ["tcp://127.0.0.1:0"], @events

    result = @binder.redirects_for_restart
    ios = @binder.listeners.map { |_l, io| io.to_i }

    ios.each { |int| assert_equal int, result[int] }
    assert result[:close_others]
  end

  def test_redirects_for_restart_env
    @binder.parse ["tcp://127.0.0.1:0"], @events

    result = @binder.redirects_for_restart_env

    @binder.listeners.each_with_index do |l, i|
      assert_equal "#{l[1].to_i}:#{l[0]}", result["PUMA_INHERIT_#{i}"]
    end
  end

  def test_close_listeners_closes_ios
    @binder.parse ["tcp://127.0.0.1:#{UniquePort.call}"], @events

    refute @binder.listeners.any? { |u, l| l.closed? }

    @binder.close_listeners

    assert @binder.listeners.all? { |u, l| l.closed? }
  end

  def test_close_listeners_closes_ios_unless_closed?
    @binder.parse ["tcp://127.0.0.1:0"], @events

    bomb = @binder.listeners.first[1]
    bomb.close
    def bomb.close; raise "Boom!"; end # the bomb has been planted

    assert @binder.listeners.any? { |u, l| l.closed? }

    @binder.close_listeners

    assert @binder.listeners.all? { |u, l| l.closed? }
  end

  def test_listeners_file_unlink_if_unix_listener
    skip UNIX_SKT_MSG unless UNIX_SKT_EXIST

    @binder.parse ["unix://test/#{name}_server.sock"], @events

    assert File.socket?("test/#{name}_server.sock")

    @binder.close_listeners

    refute File.socket?("test/#{name}_server.sock")
  end

  def test_import_from_env_listen_inherit
    @binder.parse ["tcp://127.0.0.1:0"], @events
    removals = @binder.import_from_env(@binder.redirects_for_restart_env)

    @binder.listeners.each do |url, io|
      assert_equal io.to_i, @binder.inherited_fds[url]
    end
    assert_includes removals, "PUMA_INHERIT_0"
  end

  # test socket activation with tcp
  # test socket activation with IPv6
  # test socket activation with Unix
  # test socket activation logs to events
  # test socket activation returns the right keys to remove

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

    order.each do |prot|
      assert_match prepared_paths[prot], stdout
    end
  ensure
    @binder.close_listeners if order.include?(:unix) && UNIX_SKT_EXIST
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
