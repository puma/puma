require 'mongrel'
require 'yaml'
require 'zlib'

class SimpleHandler < Mongrel::HttpHandler
    def process(request, response)
      response.start do |head,out|
        head["Content-Type"] = "text/html"
        results = "<html><body>Your request:<br /><pre>#{request.params.to_yaml}</pre><a href=\"/files\">View the files.</a></body></html>"
        if request.params["HTTP_ACCEPT_ENCODING"] == "gzip,deflate"
          head["Content-Encoding"] = "deflate"
          # send it back deflated
          out << Zlib::Deflate.deflate(results)
        else
          # no gzip supported, send it back normal
          out << results
        end
      end
    end
end

class DumbHandler < Mongrel::HttpHandler
  def process(request, response)
    response.start do |head,out|
      head["Content-Type"] = "text/html"
      out.write("test")
    end
  end
end


if ARGV.length != 3
  STDERR.puts "usage:  simpletest.rb <host> <port> <docroot>"
  exit(1)
end

config = Mongrel::Configurator.new :host => ARGV[0], :port => ARGV[1] do
  listener do
    uri "/", :handler => SimpleHandler.new
    uri "/dumb", :handler => DumbHandler.new
    uri "/files", :handler => Mongrel::DirHandler.new(ARGV[2])
  end

  trap("INT") { stop }
  run
end

puts "Mongrel running on #{ARGV[0]}:#{ARGV[1]} with docroot #{ARGV[2]}"
config.join
