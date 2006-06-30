# Copyright (c) 2005 Zed A. Shaw 
# You can redistribute it and/or modify it under the same terms as Ruby.
#
# Additional work donated by contributors.  See http://mongrel.rubyforge.org/attributions.html 
# for more information.

require 'test/unit'
require 'http11'
require 'mongrel'
require 'benchmark'
require 'digest/sha1'

include Mongrel

class HttpParserTest < Test::Unit::TestCase
    
  def test_parse_simple
    parser = HttpParser.new
    req = {}
    http = "GET / HTTP/1.1\r\n\r\n"
    nread = parser.execute(req, http, 0)
    assert nread == http.length, "Failed to parse the full HTTP request"
    assert parser.finished?, "Parser didn't finish"
    assert !parser.error?, "Parser had error"
    assert nread == parser.nread, "Number read returned from execute does not match"
    parser.reset
    assert parser.nread == 0, "Number read after reset should be 0"
  end
  
  
  def test_parse_error
    parser = HttpParser.new
    req = {}
    bad_http = "GET / SsUTF/1.1"

    error = false
    begin
      nread = parser.execute(req, bad_http, 0)
    rescue => details
      error = true
    end

    assert error, "failed to throw exception"
    assert !parser.finished?, "Parser shouldn't be finished"
    assert parser.error?, "Parser SHOULD have error"
  end

  # lame random garbage maker
  def rand_data(min, max, readable=true)
    count = min + ((rand(max)+1) *10).to_i
    res = count.to_s + "/"
    
    if readable
      res << Digest::SHA1.hexdigest(rand(count * 1000).to_s) * (count / 40)
    else
      res << Digest::SHA1.digest(rand(count * 1000).to_s) * (count / 20)
    end

    return res
  end
  

  def test_horrible_queries
    parser = HttpParser.new

    # first verify that large random get requests fail
    100.times do |c| 
      get = "GET /#{rand_data(1024, 1024+(c*1024))} HTTP/1.1\r\n"
      assert_raises Mongrel::HttpParserError do
        parser.execute({}, get, 0)
        parser.reset
      end
    end

    # then that large header names are caught
    100.times do |c|
      get = "GET /#{rand_data(10,120)} HTTP/1.1\r\nX-#{rand_data(1024, 1024+(c*1024))}: Test\r\n\r\n"
      assert_raises Mongrel::HttpParserError do
        parser.execute({}, get, 0)
        parser.reset
      end
    end

    # then that large mangled field values are caught
    100.times do |c|
      get = "GET /#{rand_data(10,120)} HTTP/1.1\r\nX-Test: #{rand_data(1024, 1024+(c*1024), false)}\r\n\r\n"
      assert_raises Mongrel::HttpParserError do
        parser.execute({}, get, 0)
        parser.reset
      end
    end

    # then large headers are rejected too
    get = "GET /#{rand_data(10,120)} HTTP/1.1\r\n"
    get << "X-Test: test\r\n" * (80 * 1024)
    assert_raises Mongrel::HttpParserError do
      parser.execute({}, get, 0)
      parser.reset
    end

    # finally just that random garbage gets blocked all the time
    10.times do |c|
      get = "GET #{rand_data(1024, 1024+(c*1024), false)} #{rand_data(1024, 1024+(c*1024), false)}\r\n\r\n"
      assert_raises Mongrel::HttpParserError do
        parser.execute({}, get, 0)
        parser.reset
      end
    end

  end



  def test_query_parse
    res = HttpRequest.query_parse("zed=1&frank=#{HttpRequest.escape('&&& ')}")
    assert res["zed"], "didn't get the request right"
    assert res["frank"], "no frank"
    assert_equal "1", res["zed"], "wrong result"
    assert_equal "&&& ", HttpRequest.unescape(res["frank"]), "wrong result"

    res = HttpRequest.query_parse("zed=1&zed=2&zed=3&frank=11;zed=45")
    assert res["zed"], "didn't get the request right"
    assert res["frank"], "no frank"
    assert_equal 4,res["zed"].length, "wrong number for zed"
    assert_equal "11",res["frank"], "wrong number for frank"
  end
  
end

