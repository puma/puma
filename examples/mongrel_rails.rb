require 'mongrel'
require 'cgi'
require 'config/environment'

class CGIFixed < ::CGI
  public :env_table
  
  def initialize(params, data, out, *args)
    @env_table = params
    @args = *args
    @input = StringIO.new(data)
    @out = out
    super(*args)
  end
  
  def args
    @args
  end
  
  def env_table
    @env_table
  end
  
  def stdinput
    @input
  end
  
  def stdoutput
    @out
  end
end


class RailsHandler < Mongrel::HttpHandler
  def initialize
    @guard = Mutex.new
  end
  
  def process(request, response)
    # not static, need to talk to rails
    return if response.socket.closed?
    
    cgi = CGIFixed.new(request.params, request.body, response.socket)
    begin

      @guard.synchronize do
        # Rails is not thread safe so must be run entirely within synchronize 
        Dispatcher.dispatch(cgi, ActionController::CgiRequest::DEFAULT_SESSION_OPTIONS, response.body)
      end

      response.send_status
      response.send_body
    rescue IOError
      @log.error("received IOError #$! when handling client.  Your web server doesn't like me.")
    rescue Object => rails_error
      @log.error("calling Dispatcher.dispatch", rails_error)
    end
  end
end

if ARGV.length != 3
  STDERR.puts "usage:  mongrel_rails.rb <host> <port> <docroot>"
  exit(1)
end

h = Mongrel::HttpServer.new(ARGV[0], ARGV[1])
h.register("/", Mongrel::DirHandler.new(ARGV[2]))
h.register("/app", RailsHandler.new)
h.run

puts "Mongrel running on #{ARGV[0]}:#{ARGV[1]} with docroot #{ARGV[2]}"

h.acceptor.join
