require 'test/unit'
require 'http11'
require 'mongrel'
require 'benchmark'

include Mongrel

class HttpParserTest < Test::Unit::TestCase
    
  def test_parse_simple
    parser = HttpParser.new
    req = {}
    http = "GET / HTTP/1.1\r\n\r\n"
    nread = parser.execute(req, http);
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
      nread = parser.execute(req, bad_http)
    rescue => details
      error = true
    end

    assert error, "failed to throw exception"
    assert !parser.finished?, "Parser shouldn't be finished"
    assert parser.error?, "Parser SHOULD have error"
  end

  def test_query_parse
    puts HttpRequest.query_parse("zed=1&frank=2").inspect
    puts HttpRequest.query_parse("zed=1&zed=2&zed=3&frank=11;zed=45").inspect

    puts Benchmark.measure {
      10000.times do |i|
        g = HttpRequest.query_parse("zed=1&zed=2&zed=3&frank=11").inspect
      end
    }        
  end


end

