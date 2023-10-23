# frozen_string_literal: true

require_relative "helper"

require "json"
require "puma/json_serialization"

class TestJSONSerialization < Minitest::Test
  parallelize_me! unless JRUBY_HEAD

  def test_json_generates_string_for_hash_with_string_keys
    value = { "key" => "value" }
    assert_puma_json_generates_string '{"key":"value"}', value
  end

  def test_json_generates_string_for_hash_with_symbol_keys
    value = { key: 'value' }
    assert_puma_json_generates_string '{"key":"value"}', value, expected_roundtrip: { "key" => "value" }
  end

  def test_generate_raises_error_for_unexpected_key_type
    value = { [1] => 'b' }
    ex = assert_raises Puma::JSONSerialization::SerializationError do
      Puma::JSONSerialization.generate value
    end
    assert_equal 'Could not serialize object of type Array as object key', ex.message
  end

  def test_json_generates_string_for_array_of_integers
    value = [1, 2, 3]
    assert_puma_json_generates_string '[1,2,3]', value
  end

  def test_json_generates_string_for_array_of_strings
    value = ["a", "b", "c"]
    assert_puma_json_generates_string '["a","b","c"]', value
  end

  def test_json_generates_string_for_nested_arrays
    value = [1, [2, [3]]]
    assert_puma_json_generates_string '[1,[2,[3]]]', value
  end

  def test_json_generates_string_for_integer
    value = 42
    assert_puma_json_generates_string '42', value
  end

  def test_json_generates_string_for_float
    value = 1.23
    assert_puma_json_generates_string '1.23', value
  end

  def test_json_escapes_strings_with_quotes
    value = 'a"'
    assert_puma_json_generates_string '"a\""', value
  end

  def test_json_escapes_strings_with_backslashes
    value = 'a\\'
    assert_puma_json_generates_string '"a\\\\"', value
  end

  def test_json_escapes_strings_with_null_byte
    value = "\x00"
    assert_puma_json_generates_string '"\u0000"', value
  end

  def test_json_escapes_strings_with_unicode_information_separator_one
    value = "\x1f"
    assert_puma_json_generates_string '"\u001F"', value
  end

  def test_json_generates_string_for_true
    value = true
    assert_puma_json_generates_string 'true', value
  end

  def test_json_generates_string_for_false
    value = false
    assert_puma_json_generates_string 'false', value
  end

  def test_json_generates_string_for_nil
    value = nil
    assert_puma_json_generates_string 'null', value
  end

  def test_generate_raises_error_for_unexpected_value_type
    value = /abc/
    ex = assert_raises Puma::JSONSerialization::SerializationError do
      Puma::JSONSerialization.generate value
    end
    assert_equal 'Unexpected value of type Regexp', ex.message
  end

  private

  def assert_puma_json_generates_string(expected_output, value_to_serialize, expected_roundtrip: nil)
    actual_output = Puma::JSONSerialization.generate(value_to_serialize)
    assert_equal expected_output, actual_output

    if value_to_serialize.nil?
      assert_nil ::JSON.parse(actual_output)
    else
      expected_roundtrip ||= value_to_serialize
      assert_equal expected_roundtrip, ::JSON.parse(actual_output)
    end
  end
end
