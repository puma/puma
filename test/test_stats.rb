require 'test/unit'
require 'mongrel/stats'

class StatsTest < Test::Unit::TestCase

  def test_sampling_speed
    s = Stats.new("test")
    t = Stats.new("time")

    10000.times { s.sample(rand(20)); t.tick }

    s.dump("FIRST")
    t.dump("FIRST")
    
    old_mean = s.mean
    old_sd = s.sd

    s.reset
    t.reset
    10000.times { s.sample(rand(20)); t.tick }
    
    s.dump("SECOND")
    t.dump("SECOND")
    assert_not_equal old_mean, s.mean
    assert_not_equal old_mean, s.sd    
  end

end
