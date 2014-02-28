# Copyright (c) 2011 Evan Phoenix
# Copyright (c) 2005 Zed A. Shaw

require 'testhelp'

include Puma

class Http11ParserTest < Test::Unit::TestCase

  def test_parse_simple
    parser = HttpParser.new
    req = {}
    http = "GET / HTTP/1.1\r\n\r\n"
    nread = parser.execute(req, http, 0)

    assert nread == http.length, "Failed to parse the full HTTP request"
    assert parser.finished?, "Parser didn't finish"
    assert !parser.error?, "Parser had error"
    assert nread == parser.nread, "Number read returned from execute does not match"

    assert_equal '/', req['REQUEST_PATH']
    assert_equal 'HTTP/1.1', req['HTTP_VERSION']
    assert_equal '/', req['REQUEST_URI']
    assert_equal 'GET', req['REQUEST_METHOD']
    assert_nil req['FRAGMENT']
    assert_nil req['QUERY_STRING']

    parser.reset
    assert parser.nread == 0, "Number read after reset should be 0"
  end

  def test_parse_dumbfuck_headers
    parser = HttpParser.new
    req = {}
    should_be_good = "GET / HTTP/1.1\r\naaaaaaaaaaaaa:++++++++++\r\n\r\n"
    nread = parser.execute(req, should_be_good, 0)
    assert_equal should_be_good.length, nread
    assert parser.finished?
    assert !parser.error?
  end

  def test_parse_error
    parser = HttpParser.new
    req = {}
    bad_http = "GET / SsUTF/1.1"

    error = false
    begin
      parser.execute(req, bad_http, 0)
    rescue
      error = true
    end

    assert error, "failed to throw exception"
    assert !parser.finished?, "Parser shouldn't be finished"
    assert parser.error?, "Parser SHOULD have error"
  end

  def test_fragment_in_uri
    parser = HttpParser.new
    req = {}
    get = "GET /forums/1/topics/2375?page=1#posts-17408 HTTP/1.1\r\n\r\n"
    assert_nothing_raised do
      parser.execute(req, get, 0)
    end
    assert parser.finished?
    assert_equal '/forums/1/topics/2375?page=1', req['REQUEST_URI']
    assert_equal 'posts-17408', req['FRAGMENT']
  end

  # lame random garbage maker
  def rand_data(min, max, readable=true)
    count = min + ((rand(max)+1) *10).to_i
    res = count.to_s + "/"

    if readable
      res << Digest::SHA1.hexdigest(rand(count * 100).to_s) * (count / 40)
    else
      res << Digest::SHA1.digest(rand(count * 100).to_s) * (count / 20)
    end

    return res
  end

  def test_max_uri_path_length
    parser = HttpParser.new
    req = {}

    # Support URI path length to a max of 2048
    path = "/" + rand_data(1000, 100)
    http = "GET #{path} HTTP/1.1\r\n\r\n"
    parser.execute(req, http, 0)
    assert_equal path, req['REQUEST_PATH']
    parser.reset

    # Raise exception if URI path length > 2048
    path = "/" + rand_data(2049, 100)
    http = "GET #{path} HTTP/1.1\r\n\r\n"
    assert_raises Puma::HttpParserError do
      parser.execute(req, http, 0)
      parser.reset
    end
  end

  def test_horrible_queries
    parser = HttpParser.new

    # then that large header names are caught
    10.times do |c|
      get = "GET /#{rand_data(10,120)} HTTP/1.1\r\nX-#{rand_data(1024, 1024+(c*1024))}: Test\r\n\r\n"
      assert_raises Puma::HttpParserError do
        parser.execute({}, get, 0)
        parser.reset
      end
    end

    # then that large mangled field values are caught
    10.times do |c|
      get = "GET /#{rand_data(10,120)} HTTP/1.1\r\nX-Test: #{rand_data(1024, 1024+(c*1024), false)}\r\n\r\n"
      assert_raises Puma::HttpParserError do
        parser.execute({}, get, 0)
        parser.reset
      end
    end

    # then large headers are rejected too
    get = "GET /#{rand_data(10,120)} HTTP/1.1\r\n"
    get << "X-Test: test\r\n" * (80 * 1024)
    assert_raises Puma::HttpParserError do
      parser.execute({}, get, 0)
      parser.reset
    end

    # finally just that random garbage gets blocked all the time
    10.times do |c|
      get = "GET #{rand_data(1024, 1024+(c*1024), false)} #{rand_data(1024, 1024+(c*1024), false)}\r\n\r\n"
      assert_raises Puma::HttpParserError do
        parser.execute({}, get, 0)
        parser.reset
      end
    end

  end
end
