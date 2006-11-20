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

  def test_boundaries_over_chunks
    hay = ["zed is a tool ba",
      "ggiethis has the baggieb",
      "aggie of baggie-baggie tricks in another ",
      "baggie"]

    total = "zed is a tool baggiethis has the baggiebaggie of baggie-baggie tricks in another baggie"

    s = BMHSearch.new("baggie", 20)

    hay.each {|h| s.find(h) }
    hay_found = s.pop
   
    s = BMHSearch.new("baggie", 20)
    s.find(total)
    total_found = s.pop

    assert_equal hay_found.length, total_found.length, "wrong number of needles found"

    total_found.length.times do |i|
      assert_equal total_found[i], hay_found[i], "boundary doesn't match"
    end
  end


  def test_fuzzing
    begin
      has_rfuzz = require 'rfuzz/random'
    rescue Object
      has_rfuzz = false
    end

    if has_rfuzz
      r = RFuzz::RandomGenerator.new
      needles = r.base64(20, 64).collect {|n| "\r\n" + n.strip }
      needles.each do |needle|
        next if needle.length == 0

        nchunks = r.num(10) + 10
        bmh = BMHSearch.new(needle, nchunks+1)
        total = ""  # used to collect the full string for compare

        # each needle is sprinkled into up to 100 chunks
        nchunks.times do
          # each chunk is up to 16k in size
          chunk = r.bytes(r.num(16 * 1024) + needle.length * 2)
          chunk.gsub! needle, ""

          # make about 60% go across boundaries
          if r.num(10) < 6
            # this one gets cut in two
            cut_at = r.num(needle.length - 1) + 1
            n1 = needle[0 ... cut_at]
            n2 = needle[cut_at .. -1]
            
            assert_equal n1+n2, needle, "oops, messed up breaking the needle"

            last_nfound = bmh.nfound
            bmh.find(chunk + n1)
            assert bmh.has_trailing?, "should have trailing on #{n1}:#{n2} on chunk length: #{chunk.length}"
            assert_equal last_nfound, bmh.nfound, "shouldn't find it yet"

            bmh.find(n2 + chunk)
            assert_equal last_nfound+1, bmh.nfound, "should have found the boundary for #{n1}:#{n2} on chunk length: #{chunk.length}"
            total << chunk + n1 + n2 + chunk
          else
            # this one is put in complete
            bmh.find(chunk + needle)
            bmh.find(chunk)

            total << chunk + needle + chunk
          end
        end

        tbmh = BMHSearch.new(needle, nchunks+1)
        tbmh.find(total)

        assert_equal total.length, bmh.total, "totals don't match"
        assert_equal tbmh.nfound, bmh.nfound, "nfound don't match"

        total_found = tbmh.pop
        hay_found = bmh.pop

        total_found.length.times do |i|
          assert_equal total_found[i], hay_found[i], "boundary doesn't match"
        end
      end
    end
  end
end

