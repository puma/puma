require 'puma/reactor'
require_relative "helper"

class TestReactor < Minitest::Test
  def test_initialization_on_jruby
    skip_unless :jruby
    @reactor = Puma::Reactor.new(:auto) { |c| reactor_wakeup c }
    assert_instance_of Puma::Reactor, @reactor
  end
end
