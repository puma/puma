require 'mongrel'
require 'yaml'

class SimpleHandler < Mongrel::HttpHandler
    def process(request, response)
      response.start do |head,out|
        head["Content-Type"] = "text/plain"
        out.write("hello!\n")
      end
    end
end

h = Mongrel::HttpServer.new("0.0.0.0", "3000")
h.register("/test", SimpleHandler.new)
h.run.join

