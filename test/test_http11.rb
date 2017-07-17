# Copyright (c) 2011 Evan Phoenix
# Copyright (c) 2005 Zed A. Shaw

require_relative "helper"

require "puma/puma_http11"

class Http11ParserTest < Minitest::Test

  def test_parse_simple
    parser = Puma::HttpParser.new
    req = {}
    http = "GET /?a=1 HTTP/1.1\r\n\r\n"
    nread = parser.execute(req, http, 0)

    assert nread == http.length, "Failed to parse the full HTTP request"
    assert parser.finished?, "Parser didn't finish"
    assert !parser.error?, "Parser had error"
    assert nread == parser.nread, "Number read returned from execute does not match"

    assert_equal '/', req['REQUEST_PATH']
    assert_equal 'HTTP/1.1', req['HTTP_VERSION']
    assert_equal '/?a=1', req['REQUEST_URI']
    assert_equal 'GET', req['REQUEST_METHOD']
    assert_nil req['FRAGMENT']
    assert_equal "a=1", req['QUERY_STRING']

    parser.reset
    assert parser.nread == 0, "Number read after reset should be 0"
  end

  def test_parse_escaping_in_query
    parser = Puma::HttpParser.new
    req = {}
    http = "GET /admin/users?search=%27%%27 HTTP/1.1\r\n\r\n"
    nread = parser.execute(req, http, 0)

    assert nread == http.length, "Failed to parse the full HTTP request"
    assert parser.finished?, "Parser didn't finish"
    assert !parser.error?, "Parser had error"
    assert nread == parser.nread, "Number read returned from execute does not match"

    assert_equal '/admin/users?search=%27%%27', req['REQUEST_URI']
    assert_equal "search=%27%%27", req['QUERY_STRING']

    parser.reset
    assert parser.nread == 0, "Number read after reset should be 0"
  end

  def test_parse_absolute_uri
    parser = Puma::HttpParser.new
    req = {}
    http = "GET http://192.168.1.96:3000/api/v1/matches/test?1=1 HTTP/1.1\r\n\r\n"
    nread = parser.execute(req, http, 0)

    assert nread == http.length, "Failed to parse the full HTTP request"
    assert parser.finished?, "Parser didn't finish"
    assert !parser.error?, "Parser had error"
    assert nread == parser.nread, "Number read returned from execute does not match"

    assert_equal "GET", req['REQUEST_METHOD']
    assert_equal 'http://192.168.1.96:3000/api/v1/matches/test?1=1', req['REQUEST_URI']
    assert_equal 'HTTP/1.1', req['HTTP_VERSION']

    assert_nil req['REQUEST_PATH']
    assert_nil req['FRAGMENT']
    assert_nil req['QUERY_STRING']

    parser.reset
    assert parser.nread == 0, "Number read after reset should be 0"

  end

  def test_parse_dumbfuck_headers
    parser = Puma::HttpParser.new
    req = {}
    should_be_good = "GET / HTTP/1.1\r\naaaaaaaaaaaaa:++++++++++\r\n\r\n"
    nread = parser.execute(req, should_be_good, 0)
    assert_equal should_be_good.length, nread
    assert parser.finished?
    assert !parser.error?
  end

  def test_parse_error
    parser = Puma::HttpParser.new
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
    parser = Puma::HttpParser.new
    req = {}
    get = "GET /forums/1/topics/2375?page=1#posts-17408 HTTP/1.1\r\n\r\n"

    parser.execute(req, get, 0)

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
    parser = Puma::HttpParser.new
    req = {}

    # Support URI path length to a max of 2048
    path = "/" + rand_data(1000, 100)
    http = "GET #{path} HTTP/1.1\r\n\r\n"
    parser.execute(req, http, 0)
    assert_equal path, req['REQUEST_PATH']
    parser.reset

    # Raise exception if URI path length > 2048
    path = "/" + rand_data(3000, 100)
    http = "GET #{path} HTTP/1.1\r\n\r\n"
    assert_raises Puma::HttpParserError do
      parser.execute(req, http, 0)
      parser.reset
    end
  end

  def test_horrible_queries
    parser = Puma::HttpParser.new

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
