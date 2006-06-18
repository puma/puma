require 'test/unit'
require 'mongrel'
require 'mongrel/redirect_handler'
require 'net/http'
require 'uri'
require 'timeout'

class TC_RedirectHandler < Test::Unit::TestCase

  def setup
    @server = Mongrel::HttpServer.new('0.0.0.0', 9998)
    @server.run
    @client = Net::HTTP.new('0.0.0.0', 9998)
  end

  def teardown
    @server.stop
  end

  def test_simple_redirect
    tester = Mongrel::RedirectHandler.new('/yo')
    @server.register("/test", tester)

    sleep(1)
    res = @client.request_get('/test')
    assert res != nil, "Didn't get a response"
    assert_equal ['/yo'], res.get_fields('Location')
  end

  def test_rewrite
    tester = Mongrel::RedirectHandler.new(/(\w+)/, '+\1+')
    @server.register("/test", tester)

    sleep(1)
    res = @client.request_get('/test/something')
    assert_equal ['/+test+/+something+'], res.get_fields('Location')
  end

end


