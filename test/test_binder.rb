require "rbconfig"
require 'test/unit'

require 'puma/binder'
require 'puma/events'

class TestBinder < Test::Unit::TestCase

  def setup
    @events = Puma::Events.new(STDOUT, STDERR)
    @binder = Puma::Binder.new(@events)
  end

  def test_localhost_addresses_dont_alter_listeners_for_tcp_addresses
    @binder.parse(["tcp://localhost:10001"], @events)

    assert_equal [], @binder.listeners
  end

  def test_localhost_addresses_dont_alter_listeners_for_ssl_addresses
    key =  File.expand_path "../../examples/puma/puma_keypair.pem", __FILE__
    cert = File.expand_path "../../examples/puma/cert_puma.pem", __FILE__

    @binder.parse(["ssl://localhost:10002?key=#{key}&cert=#{cert}"], @events)

    assert_equal [], @binder.listeners
  end

end
