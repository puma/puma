# Copyright (c) 2005 Zed A. Shaw 
# You can redistribute it and/or modify it under the same terms as Ruby.
#
# Additional work donated by contributors.  See http://mongrel.rubyforge.org/attributions.html 
# for more information.

require 'test/unit'
require 'mongrel'
require 'http11'
require File.dirname(__FILE__) + "/testhelp.rb"

include Mongrel

class BMHSearchTest < Test::Unit::TestCase

  def setup
    @needle = "needle"
  end

  def teardown
  end

  def test_operations
    to_find = "this has a needle and a need"
    s = BMHSearch.new(@needle, 10)
    assert s.needle == @needle, "internal needle does not match needle"
    assert_equal s.max_find, 10, "max_found isn't right"

    n = s.find(to_find)
    assert_equal n,1,"wrong number found"
    assert_equal n,s.nfound, "returned found and nfound don't match"

    f = s.pop
    assert f, "didn't get the locations"
    assert_equal f.length,n,"wrong number of returned finds"
    assert_equal f[0],11,"wrong location returned"

    assert_equal to_find.length, s.total, "total doesn't match searched length"
    assert s.has_trailing?, "should have trailing data"

    to_find2 = "le through a needle dude"
    n = s.find(to_find2)

    assert_equal n,2,"second find not working"
    assert_equal n,s.nfound, "nfound don't match"

    f = s.pop
    assert f, "pop after second find not working"
    assert_equal f[0],24,"first location of second find not right"
    assert_equal f[1],41,"second location of second find not right"

    assert_equal to_find.length+to_find2.length,s.total,"wrong total length"
    assert !s.has_trailing?, "should not have trailing"

    assert_raise BMHSearchError do
      11.times { s.find("this has a needle") }
    end
  end


end

