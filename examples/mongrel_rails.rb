require 'config/environment'
require 'mongrel'
require 'cgi'

begin
  require 'daemons/deamonize'
  HAVE_DAEMONS=true
rescue
  HAVE_DAEMONS=false
end


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

if ARGV.length != 2
  STDERR.puts "usage:  mongrel_rails <host> <port>"
  exit(1)
end

h = Mongrel::HttpServer.new(ARGV[0], ARGV[1])
h.register("/", Mongrel::DirHandler.new(ARGV[2]))
h.register("/app", RailsHandler.new)
h.run

h.acceptor.join
cwd = Dir.pwd

Deamonize.daemonize(log_file=File.join(cwd,"log","mongrel.log")
open("#{cwd}/log/mongrel-#{Process.pid}.pid","w") {|f| f.write(Process.pid) }

g
