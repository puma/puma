require 'mongrel'
require 'cgi'

# Creates Rails specific configuration options for people to use 
# instead of the base Configurator.
class RailsConfigurator < Mongrel::Configurator

  # Used instead of Mongrel::Configurator.uri to setup
  # a rails application at a particular URI.  Requires
  # the following options:
  #
  # * :docroot => The public dir to serve from.
  # * :environment => Rails environment to use.
  #
  # And understands the following optional settings:
  #
  # * :mime => A map of mime types.
  #
  # Because of how Rails is designed you can only have
  # one installed per Ruby interpreter (talk to them 
  # about thread safety).  This function will abort
  # with an exception if called more than once.
  def rails(location, options={})
    ops = resolve_defaults(options)
    
    # fix up some defaults
    ops[:environment] ||= "development"
    ops[:docroot] ||= "public"
    ops[:mime] ||= {}

    if @rails_handler
      raise "You can only register one RailsHandler for the whole Ruby interpreter.  Complain to the ordained Rails core about thread safety."
    end

    $orig_dollar_quote = $".clone
    ENV['RAILS_ENV'] = ops[:environment]
    require 'config/environment'
    require 'dispatcher'
    require 'mongrel/rails'
    
    @rails_handler = RailsHandler.new(ops[:docroot], ops[:mime])
  end


  # Reloads rails.  This isn't too reliable really, but
  # should work for most minimal reload purposes.  Only reliable
  # way it so stop then start the process.
  def reload!
    if not @rails_handler
      raise "Rails was not configured.  Read the docs for RailsConfigurator."
    end

    STDERR.puts "Reloading rails..."
    @rails_handler.reload!
    STDERR.puts "Done reloading rails."
    
  end
end

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
  attr_reader :guard
  
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
      begin
        cgi = Mongrel::CGIWrapper.new(request, response)
        cgi.handler = self

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


  def reload!
    @guard.synchronize do
      $".replace $orig_dollar_quote
      GC.start
      Dispatcher.reset_application!
      ActionController::Routing::Routes.reload
    end
  end
end


if $mongrel_debugging

  # Tweak the rails handler to allow for tracing
  class RailsHandler
    alias :real_process :process
    
    def process(request, response)
      MongrelDbg::trace(:rails, "REQUEST #{Time.now}\n" + request.params.to_yaml)
      
      real_process(request, response)
      
      MongrelDbg::trace(:rails, "REQUEST #{Time.now}\n" + request.params.to_yaml)
    end
  end
  
end
