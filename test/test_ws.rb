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

