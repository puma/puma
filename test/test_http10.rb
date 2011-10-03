require 'test/testhelp'

class Http10ParserTest < Test::Unit::TestCase
  include Puma

  def test_parse_simple
    parser = HttpParser.new
    req = {}
    http = "GET / HTTP/1.0\r\n\r\n"
    nread = parser.execute(req, http, 0)

    assert nread == http.length, "Failed to parse the full HTTP request"
    assert parser.finished?, "Parser didn't finish"
    assert !parser.error?, "Parser had error"
    assert nread == parser.nread, "Number read returned from execute does not match"

    assert_equal '/', req['REQUEST_PATH']
    assert_equal 'HTTP/1.0', req['HTTP_VERSION']
    assert_equal '/', req['REQUEST_URI']
    assert_equal 'GET', req['REQUEST_METHOD']    
    assert_nil req['FRAGMENT']
    assert_nil req['QUERY_STRING']
    
    parser.reset
    assert parser.nread == 0, "Number read after reset should be 0"
  end
end
