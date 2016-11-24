require "test_helper"

require "puma/events"

class TestEvents < Minitest::Test
  def test_null
    events = Puma::Events.null

    assert_kind_of Puma::NullIO, events.stdout
    assert_kind_of Puma::NullIO, events.stderr
  end

  def test_strings
    events = Puma::Events.strings

    assert_kind_of StringIO, events.stdout
    assert_kind_of StringIO, events.stderr
  end

  def test_stdio
    events = Puma::Events.stdio

    assert_equal STDOUT, events.stdout
    assert_equal STDERR, events.stderr
  end

  def test_register_callback_with_block
    res = false

    events = Puma::Events.null

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

    events = Puma::Events.null

    events.register(:exec, obj)

    events.fire(:exec)

    assert_equal true, obj.res
  end
end
