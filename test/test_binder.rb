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
    @binder.parse(["tcp://localhost:3000"], @events)

    assert_equal [], @binder.listeners
  end

  def test_localhost_addresses_dont_alter_listeners_for_ssl_addresses
    pend

    @binder.parse(["ssl://localhost:3000"], @events)

    assert_equal [], @binder.listeners
  end

end
