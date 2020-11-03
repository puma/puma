require_relative "helper"
require "puma/json"

class TestJSON < Minitest::Test
  parallelize_me! unless JRUBY_HEAD

  def test_json_generates_string_for_array_of_integers
    value = [1, 2, 3]
    assert_equal '[1,2,3]', Puma::JSON.generate(value)
  end

  def test_json_generates_string_for_nested_arrays
    value = [1, [2, [3]]]
    assert_equal '[1,[2,[3]]]', Puma::JSON.generate(value)
  end

  def test_json_generates_string_for_array_of_strings
    value = ["a", "b", "c"]
    assert_equal '["a","b","c"]', Puma::JSON.generate(value)
  end

  def test_json_escapes_strings_with_quotes
    value = ['a"']
    assert_equal '["a\""]', Puma::JSON.generate(value)
  end
end
