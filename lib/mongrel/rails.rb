require 'mongrel'
require 'cgi'

module Mongrel
  module Rails


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
      
      
      # Does the internal reload for Rails.  It might work for most cases, but
      # sometimes you get exceptions.  In that case just do a real restart.
      def reload!
        @guard.synchronize do
          $".replace $orig_dollar_quote
          GC.start
          Dispatcher.reset_application!
          ActionController::Routing::Routes.reload
        end
      end
    end

    # Creates Rails specific configuration options for people to use 
    # instead of the base Configurator.
    class RailsConfigurator < Mongrel::Configurator
      
      # Creates a single rails handler and returns it so you
      # can add it to a uri. You can actually attach it to 
      # as many URIs as you want, but this returns the 
      # same RailsHandler for each call.
      #
      # Requires the following options:
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
      # about thread safety).  Because of this the first
      # time you call this function it does all the config
      # needed to get your rails working.  After that
      # it returns the one handler you've configured.
      # This lets you attach Rails to any URI (and mulitple)
      # you want, but still protects you from threads destroying
      # your handler.
      def rails(options={})
        
        return @rails_handler if @rails_handler
        
        ops = resolve_defaults(options)
        
        # fix up some defaults
        ops[:environment] ||= "development"
        ops[:docroot] ||= "public"
        ops[:mime] ||= {}
        
        
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
        
        log "Reloading rails..."
        @rails_handler.reload!
        log "Done reloading rails."
        
      end
      
      # Takes the exact same configuration as Mongrel::Configurator (and actually calls that)
      # but sets up the additional HUP handler to call reload!.
      def setup_rails_signals(options={})
        ops = resolve_defaults(options)
        
        if RUBY_PLATFORM !~ /mswin/
          setup_signals(options)
          
          # rails reload
          trap("HUP") { 
            log "HUP signal received."
            reload!
          }
          
          log "Rails signals registered.  HUP => reload (without restart).  It might not work well."
        else
          log "WARNING:  Rails does not support signals on Win32."
        end
      end
    end
  end
end
