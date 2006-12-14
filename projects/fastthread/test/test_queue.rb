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
    6.times do
      s << q.shift
    end
    assert_equal "abcdef", s
  end

  def test_queue
    check_sequence( Queue.new )
  end

  def test_sized_queue
    check_sequence( SizedQueue.new( 6 ) )
    check_sequence( SizedQueue.new( 3 ) )
    check_sequence( SizedQueue.new( 1 ) )
  end
end 

