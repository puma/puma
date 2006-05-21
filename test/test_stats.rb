# Mongrel Web Server - A Mostly Ruby Webserver and Library
#
# Copyright (C) 2005 Zed A. Shaw zedshaw AT zedshaw dot com
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

require 'test/unit'
require 'mongrel/stats'
require 'stringio'

class StatsTest < Test::Unit::TestCase

  def test_sampling_speed
    out = StringIO.new

    s = Stats.new("test")
    t = Stats.new("time")

    10000.times { s.sample(rand(20)); t.tick }

    s.dump("FIRST", out)
    t.dump("FIRST", out)
    
    old_mean = s.mean
    old_sd = s.sd

    s.reset
    t.reset
    10000.times { s.sample(rand(20)); t.tick }
    
    s.dump("SECOND", out)
    t.dump("SECOND", out)
    assert_not_equal old_mean, s.mean
    assert_not_equal old_mean, s.sd    
  end

end
