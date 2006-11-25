require 'test/unit'
$:.unshift File.expand_path( File.join( File.dirname( __FILE__ ), "../ext" ) )
require 'fastthread'

class TestMutex < Test::Unit::TestCase
  def test_locked_p
    m = Mutex.new
    assert_equal false, m.locked?
    m.lock
    assert_equal true, m.locked?
    m.unlock
    assert_equal false, m.locked?
  end

  def test_synchronize
    m = Mutex.new
    assert !m.locked?
    m.synchronize do
      assert m.locked?
    end
    assert !m.locked?
  end

  def test_synchronize_exception
    m = Mutex.new
    assert !m.locked?
    assert_raise ArgumentError do
      m.synchronize do
        assert m.locked?
        raise ArgumentError
      end
    end
    assert !m.locked?
  end

  def test_mutual_exclusion
    s = ""
    m = Mutex.new

    ("a".."c").map do |c|
      Thread.new do
        5.times do
          m.synchronize do
            s << c
            Thread.pass
            s << c
          end
        end
      end
    end.each do |thread|
      thread.join
    end

    assert_equal 30, s.length
    assert s.match( /^(aa|bb|cc)+$/ )
  end
end 

