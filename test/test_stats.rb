
require 'test/unit'
require 'mongrel/stats'
require 'stringio'

class StatsTest < Test::Unit::TestCase

  def test_sampling_speed
    out = StringIO.new

    s = Stats.new("test")
    t = Stats.new("time")

    100.times { s.sample(rand(20)); t.tick }

    s.dump("FIRST", out)
    t.dump("FIRST", out)
    
    old_mean = s.mean
    old_sd = s.sd

    s.reset
    t.reset
    100.times { s.sample(rand(30)); t.tick }
    
    s.dump("SECOND", out)
    t.dump("SECOND", out)
    assert_not_equal old_mean, s.mean
    assert_not_equal old_mean, s.sd    
  end

end
