require 'puma/events'
require_relative "helper"

class TestEvents < Minitest::Test
  def test_register_callback_with_block
    res = false

    events = Puma::Events.new

    events.register(:exec) { res = true }

    events.fire(:exec)

    assert_equal true, res
  end

  def test_register_callback_with_object
    obj = Object.new

    def obj.res
      @res || false
    end

    def obj.call
      @res = true
    end

    events = Puma::Events.new

    events.register(:exec, obj)

    events.fire(:exec)

    assert_equal true, obj.res
  end

  def test_fire_callback_with_multiple_arguments
    res = []

    events = Puma::Events.new

    events.register(:exec) { |*args| res.concat(args) }

    events.fire(:exec, :foo, :bar, :baz)

    assert_equal [:foo, :bar, :baz], res
  end

  def test_after_booted_callback
    res = false

    events = Puma::Events.new

    events.after_booted { res = true }

    events.fire_after_booted!

    assert res
  end
end
