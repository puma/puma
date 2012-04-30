require 'puma/null_io'
require 'test/unit'

class TestNullIO < Test::Unit::TestCase
  attr_accessor :nio
  def setup
    self.nio = Puma::NullIO.new
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
    assert_nil nio.read(1,buf)
    assert_equal "", buf
  end
end
