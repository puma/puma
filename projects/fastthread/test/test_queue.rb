require 'test/unit'
if RUBY_PLATFORM == "java"
  require 'thread'
else
  $:.unshift File.expand_path( File.join( File.dirname( __FILE__ ), "../ext/fastthread" ) )
  require 'fastthread'
end

class TestQueue < Test::Unit::TestCase
  def check_sequence( q )
    range = "a".."f"

    s = ""
    e = nil

    t = Thread.new do
      begin
        for c in range
          q.push c
          s << c
          Thread.pass
        end
      rescue Exception => e
      end
    end

    for c in range
      unless t.alive?
        raise e if e
        assert_equal range.to_a.join, s, "expected all values pushed"
      end
      x = q.shift
      assert_equal c, x, "sequence error: expected #{ c } but got #{ x }"
    end
  end

  def test_queue
    check_sequence( Queue.new )
  end

  def test_sized_queue_full
    check_sequence( SizedQueue.new( 6 ) )
  end

  def test_sized_queue_half
    check_sequence( SizedQueue.new( 3 ) )
  end

  def test_sized_queue_one
    check_sequence( SizedQueue.new( 1 ) )
  end
end 

