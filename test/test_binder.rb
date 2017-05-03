require_relative "helper"

require "puma/binder"
require "puma/events"
require "puma/puma_http11"

class TestBinder < Minitest::Test
  def setup
    @events = Puma::Events.null
    @binder = Puma::Binder.new(@events)
  end

  def test_localhost_addresses_dont_alter_listeners_for_tcp_addresses
    skip_on_jruby

    @binder.parse(["tcp://localhost:10001"], @events)

    assert_equal [], @binder.listeners
  end

  def test_localhost_addresses_dont_alter_listeners_for_ssl_addresses
    skip_on_jruby

    key =  File.expand_path "../../examples/puma/puma_keypair.pem", __FILE__
    cert = File.expand_path "../../examples/puma/cert_puma.pem", __FILE__

    @binder.parse(["ssl://localhost:10002?key=#{key}&cert=#{cert}"], @events)

    assert_equal [], @binder.listeners
  end
end
