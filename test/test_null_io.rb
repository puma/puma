# frozen_string_literal: true

require_relative "helper"

require "puma/null_io"

class TestNullIO < Minitest::Test
  parallelize_me!

  attr_accessor :nio

  def setup
    self.nio = Puma::NullIO.new
  end

  def test_eof_returns_true
    assert nio.eof?
  end

  def test_gets_returns_nil
    assert_nil nio.gets
  end

  def test_string_returns_empty_string
    assert_equal "", nio.string
  end

  def test_each_never_yields
    nio.instance_variable_set(:@foo, :baz)
    nio.each { @foo = :bar }
    assert_equal :baz, nio.instance_variable_get(:@foo)
  end

  def test_read_with_no_arguments
    assert_equal "", nio.read
  end

  def test_read_with_nil_length
    assert_equal "", nio.read(nil)
  end

  def test_read_with_zero_length
    assert_equal "", nio.read(0)
  end

  def test_read_with_positive_integer_length
    assert_nil nio.read(1)
  end

  def test_read_with_negative_length
    error = assert_raises ArgumentError do
      nio.read(-42)
    end
    # 2nd match is TruffleRuby
    assert_match(/negative length -42 given|length must not be negative/, error.message)
  end

  def test_read_with_nil_buffer
    assert_equal "", nio.read(nil, nil)
    assert_equal "", nio.read(0, nil)
    assert_nil nio.read(1, nil)
  end

  class ImplicitString
    def to_str
      "ImplicitString".b
    end
  end

  def test_read_with_implicit_string_like_buffer
    assert_equal "", nio.read(nil, ImplicitString.new)
  end

  def test_read_with_invalid_buffer
    error = assert_raises TypeError do
      nio.read(nil, Object.new)
    end
    assert_includes error.message, "no implicit conversion of Object into String"

    error = assert_raises TypeError do
      nio.read(0, Object.new)
    end

    error = assert_raises TypeError do
      nio.read(1, Object.new)
    end
    assert_includes error.message, "no implicit conversion of Object into String"
  end

  def test_read_with_frozen_buffer
    # Remove when Ruby 2.4 is no longer supported
    err = defined? ::FrozenError ? ::FrozenError : ::RuntimeError

    assert_raises err do
      nio.read(nil, "".freeze)
    end

    assert_raises err do
      nio.read(0, "".freeze)
    end

    assert_raises err do
      nio.read(20, "".freeze)
    end
  end

  def test_read_with_length_and_buffer
    buf = "random_data".b
    assert_nil nio.read(1, buf)
    assert_equal "".b, buf
  end

  def test_read_with_buffer
    buf = "random_data".b
    assert_same buf, nio.read(nil, buf)
    assert_equal "", buf
  end

  def test_size
    assert_equal 0, nio.size
  end

  def test_pos
    assert_equal 0, nio.pos
  end

  def test_seek_returns_0
    assert_equal 0, nio.seek(0)
    assert_equal 0, nio.seek(100)
  end

  def test_seek_negative_raises
    error = assert_raises ArgumentError do
      nio.read(-1)
    end

    # TruffleRuby - length must not be negative
    assert_match(/negative length -1 given|length must not be negative/, error.message)
  end

  def test_sync_returns_true
    assert_equal true, nio.sync
  end

  def test_flush_returns_self
    assert_equal nio, nio.flush
  end

  def test_closed_returns_false
    assert_equal false, nio.closed?
  end

  def test_set_encoding
    assert_equal nio, nio.set_encoding(Encoding::BINARY)
  end

  def test_external_encoding
    assert_equal Encoding::ASCII_8BIT, nio.external_encoding
  end

  def test_binmode
    assert_equal nio, nio.binmode
  end

  def test_binmode?
    assert nio.binmode?
  end
end

# Run the same tests but against an empty file to
# ensure all the test behavior is accurate
class TestNullIOConformance < TestNullIO
  def setup
    # client.rb sets 'binmode` on all Tempfiles
    self.nio = ::Tempfile.create.binmode
    nio.sync = true
  end

  def teardown
    return unless nio.is_a? ::File
    nio.close
    File.unlink nio.path
  end

  def test_string_returns_empty_string
    self.nio = StringIO.new
    super
  end
end
