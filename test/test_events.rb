# frozen_string_literal: true

require 'puma/events'
require_relative "helper"

class TestEvents < PumaTest
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

  def test_before_restart_callback
    res = false

    events = Puma::Events.new

    events.before_restart { res = true }

    events.fire_before_restart!

    assert res
  end

  def test_after_stopped_callback
    res = false

    events = Puma::Events.new

    events.after_stopped { res = true }

    events.fire_after_stopped!

    assert res
  end

  def test_on_booted_deprecated_with_warning
    res = false
    events = Puma::Events.new

    _, err = capture_io do
      events.on_booted { res = true }
    end

    events.fire_after_booted!

    assert res
    assert_match(/Use 'after_booted', 'on_booted' is deprecated and will be removed in v8/, err)
  end

  def test_on_restart_deprecated_with_warning
    res = false
    events = Puma::Events.new

    _, err = capture_io do
      events.on_restart { res = true }
    end

    events.fire_before_restart!

    assert res
    assert_match(/Use 'before_restart', 'on_restart' is deprecated and will be removed in v8/, err)
  end

  def test_on_stopped_deprecated_with_warning
    res = false
    events = Puma::Events.new

    _, err = capture_io do
      events.on_stopped { res = true }
    end

    events.fire_after_stopped!

    assert res
    assert_match(/Use 'after_stopped', 'on_stopped' is deprecated and will be removed in v8/, err)
  end
end
