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

  def test_read_with_length_and_buffer
    buf = ""
    assert_nil nio.read(1, buf)
    assert_equal "", buf
  end

  def test_size
    assert_equal 0, nio.size
  end
end
