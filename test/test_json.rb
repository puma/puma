require_relative "helper"
require "puma/json"

class TestJSON < Minitest::Test
  parallelize_me! unless JRUBY_HEAD

  def test_json_generates_string_for_hash_with_string_keys
    value = { "key" => "value" }
    assert_equal '{"key":"value"}', Puma::JSON.generate(value)
  end

  def test_json_generates_string_for_hash_with_symbol_keys
    value = { key: 'value' }
    assert_equal '{"key":"value"}', Puma::JSON.generate(value)
  end

  def test_generate_raises_error_for_unexpected_key_type
    value = { [1] => 'b' }
    ex = assert_raises Puma::JSON::SerializationError do
      Puma::JSON.generate value
    end
    assert_equal 'Could not serialize object of type Array as object key', ex.message
  end

  def test_json_generates_string_for_array_of_integers
    value = [1, 2, 3]
    assert_equal '[1,2,3]', Puma::JSON.generate(value)
  end

  def test_json_generates_string_for_array_of_strings
    value = ["a", "b", "c"]
    assert_equal '["a","b","c"]', Puma::JSON.generate(value)
  end

  def test_json_generates_string_for_nested_arrays
    value = [1, [2, [3]]]
    assert_equal '[1,[2,[3]]]', Puma::JSON.generate(value)
  end

  def test_json_generates_string_for_integer
    value = 42
    assert_equal '42', Puma::JSON.generate(value)
  end

  def test_json_generates_string_for_float
    value = 1.23
    assert_equal '1.23', Puma::JSON.generate(value)
  end

  def test_json_escapes_strings_with_quotes
    value = 'a"'
    assert_equal '"a\""', Puma::JSON.generate(value)
  end

  def test_json_escapes_strings_with_backslashes
    value = 'a\\'
    assert_equal '"a\\\\"', Puma::JSON.generate(value)
  end

  def test_json_escapes_strings_with_null_byte
    value = "\x00"
    assert_equal '"\u0000"', Puma::JSON.generate(value)
  end

  def test_json_escapes_strings_with_unicode_information_separator_one
    value = "\x1f"
    assert_equal '"\u001F"', Puma::JSON.generate(value)
  end

  def test_json_generates_string_for_true
    value = true
    assert_equal 'true', Puma::JSON.generate(value)
  end

  def test_json_generates_string_for_false
    value = false
    assert_equal 'false', Puma::JSON.generate(value)
  end

  def test_json_generates_string_for_nil
    value = nil
    assert_equal 'null', Puma::JSON.generate(value)
  end

  def test_generate_raises_error_for_unexpected_value_type
    value = /abc/
    ex = assert_raises Puma::JSON::SerializationError do
      Puma::JSON.generate value
    end
    assert_equal 'Unexpected value of type Regexp', ex.message
  end
end
