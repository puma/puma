require 'mongrel'
require 'yaml'

class SimpleHandler < Mongrel::HttpHandler
    
    def process(request, response)
      response.socket.write("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nhello!\n")
    end
    
end

h = Mongrel::HttpServer.new("0.0.0.0", "3000")
h.register("/test", SimpleHandler.new)
h.run.join

