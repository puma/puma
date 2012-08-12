require 'puma/io_buffer'
require 'test/unit'

class TestIOBuffer < Test::Unit::TestCase
  attr_accessor :iobuf
  def setup
    self.iobuf = Puma::IOBuffer.new
  end

  def test_initial_size
    assert_equal 0, iobuf.used
    assert iobuf.capacity > 0
  end

  def test_append_op
    iobuf << "abc" 
    assert_equal "abc", iobuf.to_s
    iobuf << "123"
    assert_equal "abc123", iobuf.to_s
    assert_equal 6, iobuf.used
  end

  def test_append
    expected = "mary had a little lamb"
    iobuf.append("mary", " ", "had ", "a little", " lamb")
    assert_equal expected, iobuf.to_s
    assert_equal expected.length, iobuf.used
  end

  def test_reset
    iobuf << "content"
    assert_equal "content", iobuf.to_s
    iobuf.reset
    assert_equal 0, iobuf.used
    assert_equal "", iobuf.to_s
  end

end
