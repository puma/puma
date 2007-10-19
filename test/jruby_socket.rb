
# Minimal test to help debug JRuby socket issues

require 'mongrel'

include Mongrel

@server = HttpServer.new("127.0.0.1", 9997, num_processors=1)
@server.run
@server.stop(true)
