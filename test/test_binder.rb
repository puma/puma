# frozen_string_literal: true

require_relative "helper"

require "puma/binder"
require "puma/puma_http11"

# TODO: add coverage for activated & inherited binds, maybe verify sockets
#       work with reads/writes

class TestBinderBase < Minitest::Test

  HAS_IP6 = !Socket.ip_address_list.select { |ai| ai.ipv6_loopback? }.empty?

  LOOPBACK_ADDRS = Puma::Binder.new(Puma::Events.strings).loopback_addresses
    .map do |addr|
      (addr.include? ':' and !addr.start_with? '[') ? "[#{addr}]" : addr
    end.map { |addr| Regexp.escape addr }

  CERT = File.expand_path "../../examples/puma/cert_puma.pem", __FILE__

  KEY = File.expand_path "../../examples/puma/puma_keypair.pem", __FILE__

  SSL_QUERY = "?key=#{KEY}&cert=#{CERT}"

  def setup
    @events = Puma::Events.strings
    @binder = Puma::Binder.new(@events)
  end

  def teardown
    return if skipped?
    # Binder#close does this without the 'checks', but teardown should cleanup
    # no matter what happens,ie broken Binder
    @binder.instance_variable_get(:@ios).each do |sock|
      if defined?(Puma::MiniSSL::Server) && Puma::MiniSSL::Server === sock
        sock.close
      elsif sock.is_a? BasicSocket and !sock.closed?
        sock.close
      end
    end
  end

  private

  # calls Binder#parse with bind argument, returns 'log' and @listeners array
  def parse(binds)
    @binder.parse binds, @events
    [@events.stdout.string, @binder.instance_variable_get(:@listeners)]
  end

  # concats @listeners string elements (URIs) for use with Regex match tests
  def listener_string(l)
    l.map(&:first).join ''
  end

  # below assumes ssl bind of interest is the first, need to add querying
  # if ssl bind isn't the first or more than one ssl bind is used
  def ssl_context_for_binder(binder = @binder)
    binder.instance_variable_get(:@ios)[0].instance_variable_get(:@ctx)
  end
end

# Tests pass URI's (fixed, localhost, port 0, different protocols) to
# Binder#parse, then check output and/or @listener array string
# elements for maches
#
class TestBinder < TestBinderBase
  def test_localhost_addresses_dont_alter_listeners_for_tcp_addresses
    out, l = parse ["tcp://localhost:10001"]

    l_str = listener_string l

    LOOPBACK_ADDRS.each do |addr|
      assert_match %r!tcp://#{addr}:(\d+)!, out
      assert_match %r!tcp://#{addr}:(\d+)!, l_str
    end
  end

  def test_correct_zero_port
    out, _ = parse ["tcp://localhost:0"]

    port = out[%r!tcp://127.0.0.1:(\d+)!, 1].to_i

    refute_equal 0, port
  end

  def test_logs_all_localhost_bindings
    out, _ = parse ["tcp://localhost:0"]

    LOOPBACK_ADDRS.each { |addr| assert_match %r!tcp://#{addr}:(\d+)!, out }
  end

  def test_correct_zero_port_ssl
    out, _ = parse ["ssl://localhost:0#{SSL_QUERY}"]

    port = out[%r!ssl://127.0.0.1:(\d+)!, 1].to_i

    refute_equal 0, port

    LOOPBACK_ADDRS.each { |addr| assert_match %r!ssl://#{addr}:(\d+)!, out }
  end

  def test_ios_and_listeners_correct_length
    out, l = parse ["ssl://localhost:0#{SSL_QUERY}", "tcp://localhost:0"]

    len = 2 * LOOPBACK_ADDRS.length

    assert len, out.lines
    assert len, l.length
  end

  def test_double_ssl_then_tcp_both_localhost
    out, l = parse ["ssl://localhost:0#{SSL_QUERY}", "tcp://localhost:0"]

    l_str = listener_string l

    LOOPBACK_ADDRS.each do |addr|
      assert_match %r!ssl://#{addr}:(\d+)!, out
      assert_match %r!tcp://#{addr}:(\d+)!, out
      assert_match %r!ssl://#{addr}:(\d+)!, l_str
      assert_match %r!tcp://#{addr}:(\d+)!, l_str
   end
  end

  def test_double_unix_then_tcp
    mult_binds [:unix, :tcp]
  end

  def test_double_tcp_then_unix
    mult_binds [:unix, :tcp]
  end

  def test_ipv6
    # TODO: Ubuntu & macOS have the below error
    # SocketError: getaddrinfo: nodename nor servname provided, or not known
    skip unless HAS_IP6 && windows?
    out, _ = parse ["tcp://[::1]:0"]
    assert_match %r!tcp://\[::1\]:(\d+)!, out
  end

  private

  def mult_binds(ary)
    skip UNIX_SKT_MSG if ary.include?(:unix) && !UNIX_SKT_EXIST

    binds = []

    uri_ssl = "ssl://127.0.0.1:#{UniquePort.call}"
    uri_tcp = "tcp://127.0.0.1:#{UniquePort.call}"

    if ary.include? :unix
      path_unix = "test/#{name}_server.sock"
      uri_unix  ="unix://#{path_unix}"
    end

    ary.each do |type|
      binds <<
        case type
        when :ssl  then uri_ssl
        when :tcp  then uri_tcp
        when :unix then uri_unix
        end
    end

    out, _ = parse binds

    assert(out.include? uri_ssl)  if ary.include? :ssl
    assert(out.include? uri_tcp)  if ary.include? :tcp
    assert(out.include? uri_unix) if ary.include? :unix

  ensure
    if UNIX_SKT_EXIST
      @binder.close
      File.unlink(path_unix) if File.exist? path_unix
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

    assert_equal keystore, ssl_context_for_binder.keystore
    assert_equal ssl_cipher_list, ssl_context_for_binder.ssl_cipher_list
  end
end

class TestBinderMRI < TestBinderBase
  def setup
    skip_on :jruby
    super
  end

  def test_localhost_addresses_dont_alter_listeners_for_ssl_addresses
    out, l = parse ["ssl://localhost:10002#{SSL_QUERY}"]

    strings = l.map(&:first)
    strings.each { |s| assert out.include?(s) }
  end

  def test_binder_parses_ssl_cipher_filter
    ssl_cipher_filter = "AES@STRENGTH"

    @binder.parse(["ssl://0.0.0.0#{SSL_QUERY}&ssl_cipher_filter=#{ssl_cipher_filter}"], @events)

    assert_equal ssl_cipher_filter, ssl_context_for_binder.ssl_cipher_filter
  end

  def test_binder_parses_tlsv1_disabled
    @binder.parse(["ssl://0.0.0.0#{SSL_QUERY}&no_tlsv1=true"], @events)

    assert ssl_context_for_binder.no_tlsv1
  end

  def test_binder_parses_tlsv1_enabled
    @binder.parse(["ssl://0.0.0.0#{SSL_QUERY}&no_tlsv1=false"], @events)

    refute ssl_context_for_binder.no_tlsv1
  end

  def test_binder_parses_tlsv1_tlsv1_1_unspecified_defaults_to_enabled
    @binder.parse(["ssl://0.0.0.0#{SSL_QUERY}"], @events)

    refute ssl_context_for_binder.no_tlsv1
    refute ssl_context_for_binder.no_tlsv1_1
  end

  def test_binder_parses_tlsv1_1_disabled
    @binder.parse(["ssl://0.0.0.0#{SSL_QUERY}&no_tlsv1_1=true"], @events)

    assert ssl_context_for_binder.no_tlsv1_1
  end

  def test_binder_parses_tlsv1_1_enabled
    @binder.parse(["ssl://0.0.0.0#{SSL_QUERY}&no_tlsv1_1=false"], @events)

    refute ssl_context_for_binder.no_tlsv1_1
  end
end
