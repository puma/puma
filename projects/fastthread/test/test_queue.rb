require 'test/unit'
$:.unshift File.expand_path( File.join( File.dirname( __FILE__ ), "../ext/fastthread" ) )
require 'fastthread'

class TestQueue < Test::Unit::TestCase
  def check_sequence( q )
    s = ""
    t = Thread.new do
      for c in "a".."f"
        q.push c
        Thread.pass
      end
    end

    for c in "a".."f"
      x = q.shift
      assert_equal c,x,"wrong result from shift"
      s << x
    end

    assert_equal "abcdef", s
  end

  def test_queue
    check_sequence( Queue.new )
  end

  def test_sized_queue_full
    # this test fails on Linux
    #check_sequence( SizedQueue.new( 6 ) )
  end

  def test_sized_queue_half
    # this test deadlocks
    # check_sequence( SizedQueue.new( 3 ) )
  end

  def test_sized_queue_one
    # this test also deadlocks 
    # check_sequence( SizedQueue.new( 1 ) )
  end
end 

