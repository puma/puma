require 'test/unit'
require 'net/http'
require 'mongrel'
require 'timeout'

include Mongrel;

class TestHandler < Mongrel::HttpHandler
    attr_reader :ran_test
    
    def process(request, response)
        @ran_test = true
        response.socket.write("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nhello!\n")
    end
end
		

class WSTest < Test::Unit::TestCase

    def test_simple_server
        h = HttpServer.new("127.0.0.1", 9998)
        tester = TestHandler.new
        h.register("/test", tester)
        h.run 

        sleep(3)
        res = Net::HTTP.get(URI.parse('http://localhost:9998/test'))
        assert res != nil, "Didn't get a response"
        assert tester.ran_test, "Handler didn't really run"
    end

end

