require 'mongrel'
require_gem 'rails'

# Implements a handler that can run Rails and serve files out of the
# Rails application's public directory.  This lets you run your Rails
# application with Mongrel during development and testing, then use it
# also in production behind a server that's better at serving the 
# static files.
#
# The RailsHandler takes a mime_map parameter which is a simple suffix=mimetype
# mapping that it should add to the list of valid mime types.
#
# It also supports page caching directly and will try to resolve a request
# in the following order:
#
# * If the requested exact PATH_INFO exists as a file then serve it.
# * If it exists at PATH_INFO+".html" exists then serve that.
# * Finally, construct a Mongrel::CGIWrapper and run Dispatcher.dispath to have Rails go.
#
# This means that if you are using page caching it will actually work with Mongrel
# and you should see a decent speed boost (but not as fast as if you use lighttpd).
#
# An additional feature you can use is 
class RailsHandler < Mongrel::HttpHandler
  attr_reader :files

  def initialize(dir, mime_map = {})
    @files = Mongrel::DirHandler.new(dir,false)
    @guard = Mutex.new
    
    # register the requested mime types
    mime_map.each {|k,v| Mongrel::DirHandler::add_mime_type(k,v) }
  end
  
  # Attempts to resolve the request as follows:
  #
  #
  # * If the requested exact PATH_INFO exists as a file then serve it.
  # * If it exists at PATH_INFO+".html" exists then serve that.
  # * Finally, construct a Mongrel::CGIWrapper and run Dispatcher.dispath to have Rails go.
  def process(request, response)
    return if response.socket.closed?

    path_info = request.params[Mongrel::Const::PATH_INFO]
    page_cached = request.params[Mongrel::Const::PATH_INFO] + ".html"

    if @files.can_serve(path_info)
      # File exists as-is so serve it up
      @files.process(request,response)
    elsif @files.can_serve(page_cached)
      # possible cached page, serve it up      
      request.params[Mongrel::Const::PATH_INFO] = page_cached
      @files.process(request,response)
    else
      cgi = Mongrel::CGIWrapper.new(request, response)
      cgi.handler = self

      begin
        @guard.synchronize do
          # Rails is not thread safe so must be run entirely within synchronize 
          Dispatcher.dispatch(cgi, ActionController::CgiRequest::DEFAULT_SESSION_OPTIONS, response.body)
        end

        # This finalizes the output using the proper HttpResponse way
        cgi.out {""}
      rescue Errno::EPIPE
        # ignored
      rescue Object => rails_error
        STDERR.puts "Error calling Dispatcher.dispatch #{rails_error.inspect}"
        STDERR.puts rails_error.backtrace.join("\n")
      end
    end
  end

end
