require 'mongrel'
require 'yaml'

class SimpleHandler < Mongrel::HttpHandler
    def process(request, response)
      response.start do |head,out|
        head["Content-Type"] = "text/html"
        out << "<html><body>Your request:<br />"
        out << "<pre>#{request.params.to_yaml}</pre>"
        out << "<a href=\"/files\">View the files.</a></body></html>"
      end
    end
end

if ARGV.length != 3
  STDERR.puts "usage:  simpletest.rb <host> <port> <docroot>"
  exit(1)
end

h = Mongrel::HttpServer.new(ARGV[0], ARGV[1])
h.register("/", SimpleHandler.new)
h.register("/files", Mongrel::DirHandler.new(ARGV[2]))
h.run

puts "Mongrel running on #{ARGV[0]}:#{ARGV[1]} with docroot #{ARGV[2]}"

h.acceptor.join
