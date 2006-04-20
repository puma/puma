require 'socket'
require 'http11'
require 'tempfile'
require 'thread'
require 'stringio'
require 'mongrel/cgi'
require 'mongrel/handlers'
require 'mongrel/command'
require 'mongrel/tcphack'
require 'yaml'
require 'time'
require 'rubygems' 


begin
  require 'sendfile'
  STDERR.puts "** You have sendfile installed, will use that to serve files."
rescue Object
  # do nothing
end

# Mongrel module containing all of the classes (include C extensions) for running
# a Mongrel web server.  It contains a minimalist HTTP server with just enough
# functionality to service web application requests fast as possible.
module Mongrel

  class URIClassifier
    # Returns the URIs that have been registered with this classifier so far.
    # The URIs returned should not be modified as this will cause a memory leak.
    # You can use this to inspect the contents of the URIClassifier.
    def uris
      @handler_map.keys
    end

    # Simply does an inspect that looks like a Hash inspect.
    def inspect
      @handler_map.inspect
    end
  end


  # Used to stop the HttpServer via Thread.raise.
  class StopServer < Exception
  end


  # Every standard HTTP code mapped to the appropriate message.  These are
  # used so frequently that they are placed directly in Mongrel for easy
  # access rather than Mongrel::Const.
  HTTP_STATUS_CODES = {  
    100  => 'Continue', 
    101  => 'Switching Protocols', 
    200  => 'OK', 
    201  => 'Created', 
    202  => 'Accepted', 
    203  => 'Non-Authoritative Information', 
    204  => 'No Content', 
    205  => 'Reset Content', 
    206  => 'Partial Content', 
    300  => 'Multiple Choices', 
    301  => 'Moved Permanently', 
    302  => 'Moved Temporarily', 
    303  => 'See Other', 
    304  => 'Not Modified', 
    305  => 'Use Proxy', 
    400  => 'Bad Request', 
    401  => 'Unauthorized', 
    402  => 'Payment Required', 
    403  => 'Forbidden', 
    404  => 'Not Found', 
    405  => 'Method Not Allowed', 
    406  => 'Not Acceptable', 
    407  => 'Proxy Authentication Required', 
    408  => 'Request Time-out', 
    409  => 'Conflict', 
    410  => 'Gone', 
    411  => 'Length Required', 
    412  => 'Precondition Failed', 
    413  => 'Request Entity Too Large', 
    414  => 'Request-URI Too Large', 
    415  => 'Unsupported Media Type', 
    500  => 'Internal Server Error', 
    501  => 'Not Implemented', 
    502  => 'Bad Gateway', 
    503  => 'Service Unavailable', 
    504  => 'Gateway Time-out', 
    505  => 'HTTP Version not supported'
  }

  

  # Frequently used constants when constructing requests or responses.  Many times
  # the constant just refers to a string with the same contents.  Using these constants
  # gave about a 3% to 10% performance improvement over using the strings directly.
  # Symbols did not really improve things much compared to constants.
  #
  # While Mongrel does try to emulate the CGI/1.2 protocol, it does not use the REMOTE_IDENT,
  # REMOTE_USER, or REMOTE_HOST parameters since those are either a security problem or 
  # too taxing on performance.
  module Const
    DATE = "Date".freeze

    # This is the part of the path after the SCRIPT_NAME.  URIClassifier will determine this.
    PATH_INFO="PATH_INFO".freeze

    # This is the intial part that your handler is identified as by URIClassifier.
    SCRIPT_NAME="SCRIPT_NAME".freeze

    # The original URI requested by the client.  Passed to URIClassifier to build PATH_INFO and SCRIPT_NAME.
    REQUEST_URI='REQUEST_URI'.freeze

    MONGREL_VERSION="0.3.12.5".freeze

    # The standard empty 404 response for bad requests.  Use Error4040Handler for custom stuff.
    ERROR_404_RESPONSE="HTTP/1.1 404 Not Found\r\nConnection: close\r\nServer: #{MONGREL_VERSION}\r\n\r\nNOT FOUND".freeze

    CONTENT_LENGTH="CONTENT_LENGTH".freeze

    # A common header for indicating the server is too busy.  Not used yet.
    ERROR_503_RESPONSE="HTTP/1.1 503 Service Unavailable\r\n\r\nBUSY".freeze

    # The basic max request size we'll try to read.
    CHUNK_SIZE=(4 * 1024)

    # This is the maximum header that is allowed before a client is booted.  The parser detects
    # this, but we'd also like to do this as well.
    MAX_HEADER=1024 * (80 + 32)

    # Maximum request body size before it is moved out of memory and into a tempfile for reading.
    MAX_BODY=MAX_HEADER

    # A frozen format for this is about 15% faster
    STATUS_FORMAT = "HTTP/1.1 %d %s\r\nContent-Length: %d\r\nConnection: close\r\n".freeze
    CONTENT_TYPE = "Content-Type".freeze
    LAST_MODIFIED = "Last-Modified".freeze
    ETAG = "ETag".freeze
    SLASH = "/".freeze
    REQUEST_METHOD="REQUEST_METHOD".freeze
    GET="GET".freeze
    HEAD="HEAD".freeze
    # ETag is based on the apache standard of hex mtime-size-inode (inode is 0 on win32)
    ETAG_FORMAT="\"%x-%x-%x\"".freeze
    HEADER_FORMAT="%s: %s\r\n".freeze
    LINE_END="\r\n".freeze
    REMOTE_ADDR="REMOTE_ADDR".freeze
    HTTP_X_FORWARDED_FOR="HTTP_X_FORWARDED_FOR".freeze
  end


  # When a handler is found for a registered URI then this class is constructed
  # and passed to your HttpHandler::process method.  You should assume that 
  # *one* handler processes all requests.  Included in the HttpRequest is a
  # HttpRequest.params Hash that matches common CGI params, and a HttpRequest.body
  # which is a string containing the request body (raw for now).
  #
  # The HttpeRequest.initialize method will convert any request that is larger than
  # Const::MAX_BODY into a Tempfile and use that as the body.  Otherwise it uses 
  # a StringIO object.  To be safe, you should assume it works like a file.  
  class HttpRequest
    attr_reader :body, :params

    # You don't really call this.  It's made for you.
    # Main thing it does is hook up the params, and store any remaining
    # body data into the HttpRequest.body attribute.
    def initialize(params, initial_body, socket)
      @params = params
      @socket = socket

      clen = params[Const::CONTENT_LENGTH].to_i - initial_body.length
      
      if clen > Const::MAX_BODY
        @body = Tempfile.new(self.class.name)
        @body.binmode
      else
        @body = StringIO.new
      end

      begin
        @body.write(initial_body)

        # write the odd sized chunk first
        clen -= @body.write(@socket.read(clen % Const::CHUNK_SIZE))
        
        # then stream out nothing but perfectly sized chunks
        while clen > 0
          data = @socket.read(Const::CHUNK_SIZE)
          # have to do it this way since @socket.eof? causes it to block
          raise "Socket closed or read failure" if not data or data.length != Const::CHUNK_SIZE
          clen -= @body.write(data)
        end

        # rewind to keep the world happy
        @body.rewind
      rescue Object
        # any errors means we should delete the file, including if the file is dumped
        STDERR.puts "Error reading request: #$!"
        @body.delete if @body.class == Tempfile
        @body = nil # signals that there was a problem
      end
    end

    def self.escape(s)
      s.to_s.gsub(/([^ a-zA-Z0-9_.-]+)/n) {
        '%'+$1.unpack('H2'*$1.size).join('%').upcase
      }.tr(' ', '+') 
    end


    def self.unescape(s)
      s.tr('+', ' ').gsub(/((?:%[0-9a-fA-F]{2})+)/n){
        [$1.delete('%')].pack('H*')
      } 
    end


    def self.query_parse(qs, d = '&;')
      params = {}
      (qs||'').split(/[#{d}] */n).inject(params) { |h,p|
        k, v=unescape(p).split('=',2)
        if cur = params[k]
          if cur.class == Array
            params[k] << v
          else
            params[k] = [cur, v]
          end
        else
          params[k] = v
        end
      }

      return params
    end

  end


  # This class implements a simple way of constructing the HTTP headers dynamically
  # via a Hash syntax.  Think of it as a write-only Hash.  Refer to HttpResponse for
  # information on how this is used.
  #
  # One consequence of this write-only nature is that you can write multiple headers
  # by just doing them twice (which is sometimes needed in HTTP), but that the normal
  # semantics for Hash (where doing an insert replaces) is not there.
  class HeaderOut
    attr_reader :out

    def initialize(out)
      @out = out
    end

    # Simply writes "#{key}: #{value}" to an output buffer.
    def[]=(key,value)
      @out.write(Const::HEADER_FORMAT % [key, value])
    end
    
  end

  # Writes and controls your response to the client using the HTTP/1.1 specification.
  # You use it by simply doing:
  #
  #  response.start(200) do |head,out|
  #    head['Content-Type'] = 'text/plain'
  #    out.write("hello\n")
  #  end
  #
  # The parameter to start is the response code--which Mongrel will translate for you
  # based on HTTP_STATUS_CODES.  The head parameter is how you write custom headers.
  # The out parameter is where you write your body.  The default status code for 
  # HttpResponse.start is 200 so the above example is redundant.
  # 
  # As you can see, it's just like using a Hash and as you do this it writes the proper
  # header to the output on the fly.  You can even intermix specifying headers and 
  # writing content.  The HttpResponse class with write the things in the proper order
  # once the HttpResponse.block is ended.
  #
  # You may also work the HttpResponse object directly using the various attributes available
  # for the raw socket, body, header, and status codes.  If you do this you're on your own.
  # A design decision was made to force the client to not pipeline requests.  HTTP/1.1 
  # pipelining really kills the performance due to how it has to be handled and how 
  # unclear the standard is.  To fix this the HttpResponse gives a "Connection: close"
  # header which forces the client to close right away.  The bonus for this is that it
  # gives a pretty nice speed boost to most clients since they can close their connection
  # immediately.
  #
  # One additional caveat is that you don't have to specify the Content-length header
  # as the HttpResponse will write this for you based on the out length.
  class HttpResponse
    attr_reader :socket
    attr_reader :body
    attr_reader :header
    attr_reader :status
    attr_writer :status
    attr_reader :body_sent
    attr_reader :header_sent
    attr_reader :status_sent
    
    def initialize(socket)
      @socket = socket
      @body = StringIO.new
      @status = 404
      @header = HeaderOut.new(StringIO.new)
      @header[Const::DATE] = Time.now.httpdate
      @body_sent = false
      @header_sent = false
      @status_sent = false
    end

    # Receives a block passing it the header and body for you to work with.
    # When the block is finished it writes everything you've done to 
    # the socket in the proper order.  This lets you intermix header and
    # body content as needed.  Handlers are able to modify pretty much
    # any part of the request in the chain, and can stop further processing
    # by simple passing "finalize=true" to the start method.  By default
    # all handlers run and then mongrel finalizes the request when they're
    # all done.
    def start(status=200, finalize=false)
      @status = status.to_i
      yield @header, @body
      finished if finalize
    end

    # Primarily used in exception handling to reset the response output in order to write
    # an alternative response.  It will abort with an exception if you have already
    # sent the header or the body.  This is pretty catastrophic actually.
    def reset
      if @body_sent
        raise "You have already sent the request body."
      elsif @header_sent
        raise "You have already sent the request headers."
      else
        @header.out.rewind
        @body.rewind
      end
    end

    def send_status(content_length=nil)
      if not @status_sent
	content_length ||= @body.length
        @socket.write(Const::STATUS_FORMAT % [status, HTTP_STATUS_CODES[@status], content_length])
        @status_sent = true
      end
    end

    def send_header
      if not @header_sent
        @header.out.rewind
        @socket.write(@header.out.read + Const::LINE_END)
        @header_sent = true
      end
    end

    def send_body
      if not @body_sent
        @body.rewind
        # connection: close is also added to ensure that the client does not pipeline.
        @socket.write(@body.read)
        @body_sent = true
      end
    end 

    # Appends the contents of +path+ to the response stream.  The file is opened for binary
    # reading and written in chunks to the socket.  If the 
    # <a href="http://rubyforge.org/projects/ruby-sendfile">sendfile</a> library is found,
    # it is used to send the file, often with greater speed and less memory/cpu usage.
    def send_file(path)
      File.open(path, "rb") do |f|
        if @socket.respond_to? :sendfile
          @socket.sendfile(f)
        else
          while chunk = f.read(Const::CHUNK_SIZE)
            @socket.write(chunk)
          end
        end
	  end
    rescue EOFError,Errno::ECONNRESET,Errno::EPIPE,Errno::EINVAL,Errno::EBADF
      # ignore these since it means the client closed off early
      STDERR.puts "Client closed socket requesting file #{req}: #$!"
    end

    def write(data)
      @socket.write(data)
    end

    # This takes whatever has been done to header and body and then writes it in the
    # proper format to make an HTTP/1.1 response.
    def finished
      send_status
      send_header
      send_body
    end

    def done
      (@status_sent and @header_sent and @body_sent)
    end

  end
  



  # This is the main driver of Mongrel, while the Mognrel::HttpParser and Mongrel::URIClassifier
  # make up the majority of how the server functions.  It's a very simple class that just
  # has a thread accepting connections and a simple HttpServer.process_client function
  # to do the heavy lifting with the IO and Ruby.  
  #
  # You use it by doing the following:
  #
  #   server = HttpServer.new("0.0.0.0", 3000)
  #   server.register("/stuff", MyNifterHandler.new)
  #   server.run.join
  #
  # The last line can be just server.run if you don't want to join the thread used.
  # If you don't though Ruby will mysteriously just exit on you.
  #
  # Ruby's thread implementation is "interesting" to say the least.  Experiments with
  # *many* different types of IO processing simply cannot make a dent in it.  Future
  # releases of Mongrel will find other creative ways to make threads faster, but don't
  # hold your breath until Ruby 1.9 is actually finally useful.
  class HttpServer
    attr_reader :acceptor
    attr_reader :workers
    attr_reader :classifier
    attr_reader :host
    attr_reader :port

    # Creates a working server on host:port (strange things happen if port isn't a Number).
    # Use HttpServer::run to start the server and HttpServer.acceptor.join to 
    # join the thread that's processing incoming requests on the socket.
    #
    # The num_processors optional argument is the maximum number of concurrent
    # processors to accept, anything over this is closed immediately to maintain
    # server processing performance.  This may seem mean but it is the most efficient
    # way to deal with overload.  Other schemes involve still parsing the client's request
    # which defeats the point of an overload handling system.
    # 
    # The timeout parameter is a sleep timeout (in hundredths of a second) that is placed between 
    # socket.accept calls in order to give the server a cheap throttle time.  It defaults to 0 and
    # actually if it is 0 then the sleep is not done at all.
    def initialize(host, port, num_processors=(2**30-1), timeout=0)
      @socket = TCPServer.new(host, port) 
      @classifier = URIClassifier.new
      @host = host
      @port = port
      @workers = ThreadGroup.new
      @timeout = timeout
      @num_processors = num_processors
      @death_time = 60
    end
    

    # Does the majority of the IO processing.  It has been written in Ruby using
    # about 7 different IO processing strategies and no matter how it's done 
    # the performance just does not improve.  It is currently carefully constructed
    # to make sure that it gets the best possible performance, but anyone who
    # thinks they can make it faster is more than welcome to take a crack at it.
    def process_client(client)
      begin
        parser = HttpParser.new
        params = {}

        data = client.readpartial(Const::CHUNK_SIZE)

        while true
          nread = parser.execute(params, data)

          if parser.finished?
            script_name, path_info, handlers = @classifier.resolve(params[Const::REQUEST_URI])

            if handlers
              params[Const::PATH_INFO] = path_info
              params[Const::SCRIPT_NAME] = script_name
              params[Const::REMOTE_ADDR] = params[Const::HTTP_X_FORWARDED_FOR] || client.peeraddr.last
              
              request = HttpRequest.new(params, data[nread ... data.length] || "", client)
              
              # in the case of large file uploads the user could close the socket, so skip those requests
              break if request.body == nil

              # request is good so far, continue processing the response
              response = HttpResponse.new(client)
              
              handlers.each do |handler|
                handler.process(request, response)
                break if response.done
              end
              
              if not response.done
                response.finished
              end
            else
              client.write(Const::ERROR_404_RESPONSE)
            end
          
            break #done
          else
            # gotta stream and read again until we can get the parser to be character safe
            # TODO: make this more efficient since this means we're parsing a lot repeatedly
            if data.length >= Const::MAX_HEADER
              raise HttpParserError.new("HEADER is longer than allowed, aborting client early.")
            end
            
            parser.reset
            data << client.readpartial(Const::CHUNK_SIZE)
          end
        end
      rescue EOFError,Errno::ECONNRESET,Errno::EPIPE,Errno::EINVAL
        # ignored
      rescue HttpParserError
        STDERR.puts "#{Time.now}: BAD CLIENT (#{params[Const::HTTP_X_FORWARDED_FOR] || client.peeraddr.last}): #$!"
        STDERR.puts "REQUEST DATA: #{data}"
      rescue => details
        STDERR.puts "#{Time.now}: ERROR: #$!"
        STDERR.puts details.backtrace.join("\n")
      ensure
        client.close
      end
    end

    # Used internally to kill off any worker threads that have taken too long
    # to complete processing.  Only called if there are too many processors
    # currently servicing.
    def reap_dead_workers(worker_list)
      mark = Time.now
      worker_list.each do |w|
        w[:started_on] = Time.now if not w[:started_on]

        if mark - w[:started_on] > @death_time + @timeout
          STDERR.puts "Thread #{w.inspect} is too old, killing."
          w.raise(StopServer.new("Timed out thread."))
        end
      end
    end
      

    # Runs the thing.  It returns the thread used so you can "join" it.  You can also
    # access the HttpServer::acceptor attribute to get the thread later.
    def run
      BasicSocket.do_not_reverse_lookup=true

      @acceptor = Thread.new do
        while true
          begin
            client = @socket.accept
            worker_list = @workers.list

            if worker_list.length >= @num_processors
              STDERR.puts "Server overloaded with #{worker_list.length} processors (#@num_processors max). Dropping connection."
              client.close
              reap_dead_workers(worker_list)
            else
              thread = Thread.new do
                process_client(client)
              end
              
              thread[:started_on] = Time.now
              thread.priority=1
              @workers.add(thread)
              
              sleep @timeout/100 if @timeout > 0
            end
          rescue StopServer
            STDERR.puts "Server stopped.  Exiting."
            @socket.close if not @socket.closed?
            break
          rescue Errno::EMFILE
            STDERR.puts "Too many open files.  Try increasing ulimits."
            sleep 0.5
          end
        end

        # troll through the threads that are waiting and kill any that take too long
        @death_time = 10
        shutdown_start = Time.now
        
        while @workers.list.length > 0
          waited_for = (Time.now - shutdown_start).ceil
          STDERR.print "Shutdown waited #{waited_for} for #{@workers.list.length} requests, could take #{@death_time + @timeout} seconds.\r" if @workers.list.length > 0
          sleep 1
          reap_dead_workers(@workers.list)
        end
      end

      return @acceptor
    end

    
    # Simply registers a handler with the internal URIClassifier.  When the URI is
    # found in the prefix of a request then your handler's HttpHandler::process method
    # is called.  See Mongrel::URIClassifier#register for more information.
    #
    # If you set in_front=true then the passed in handler will be put in front in the list.
    def register(uri, handler, in_front=false)
      script_name, path_info, handlers = @classifier.resolve(uri)

      if not handlers
        @classifier.register(uri, [handler])
      else
        if path_info.length == 0 or (script_name == Const::SLASH and path_info == Const::SLASH)
          if in_front
            handlers.unshift(handler)
          else
            handlers << handler
          end
        else
          @classifier.register(uri, [handler])
        end
      end
    end

    # Removes any handlers registered at the given URI.  See Mongrel::URIClassifier#unregister
    # for more information.  Remember this removes them *all* so the entire
    # processing chain goes away.
    def unregister(uri)
      @classifier.unregister(uri)
    end

    # Stops the acceptor thread and then causes the worker threads to finish
    # off the request queue before finally exiting.
    def stop
      stopper = Thread.new do 
        exc = StopServer.new
        @acceptor.raise(exc)
      end
      stopper.priority = 10
    end

  end


  # Implements a simple DSL for configuring a Mongrel server for your 
  # purposes.  More used by framework implementers to setup Mongrel
  # how they like, but could be used by regular folks to add more things
  # to an existing mongrel configuration.
  #
  # It is used like this:
  #
  #   require 'mongrel'
  #   config = Mongrel::Configurator.new :host => "127.0.0.1" do
  #     listener :port => 3000 do
  #       uri "/app", :handler => Mongrel::DirHandler.new(".", load_mime_map("mime.yaml"))
  #     end
  #     run
  #   end
  # 
  # This will setup a simple DirHandler at the current directory and load additional
  # mime types from mimy.yaml.  The :host => "127.0.0.1" is actually not 
  # specific to the servers but just a hash of default parameters that all 
  # server or uri calls receive.
  #
  # When you are inside the block after Mongrel::Configurator.new you can simply
  # call functions that are part of Configurator (like server, uri, daemonize, etc)
  # without having to refer to anything else.  You can also call these functions on 
  # the resulting object directly for additional configuration.
  #
  # A major thing about Configurator is that it actually lets you configure 
  # multiple listeners for any hosts and ports you want.  These are kept in a
  # map config.listeners so you can get to them.
  class Configurator
    attr_reader :listeners
    attr_reader :defaults
    attr_reader :needs_restart

    # You pass in initial defaults and then a block to continue configuring.
    def initialize(defaults={}, &blk)
      @listeners = {}
      @defaults = defaults
      @needs_restart = false
      
      if blk
        cloaker(&blk).bind(self).call
      end
    end
    
    # Do not call this.  You were warned.
    def cloaker &blk
      (class << self; self; end).class_eval do
        define_method :cloaker_, &blk
        meth = instance_method( :cloaker_ )
        remove_method :cloaker_
        meth
      end
    end
    
    # This will resolve the given options against the defaults.
    # Normally just used internally.
    def resolve_defaults(options)
      options.merge(@defaults)
    end
    
    # Starts a listener block.  This is the only one that actually takes
    # a block and then you make Configurator.uri calls in order to setup
    # your URIs and handlers.  If you write your Handlers as GemPlugins
    # then you can use load_plugins and plugin to load them.
    # 
    # It expects the following options (or defaults):
    # 
    # * :host => Host name to bind.
    # * :port => Port to bind.
    # * :num_processors => The maximum number of concurrent threads allowed.  (950 default)
    # * :timeout => 1/100th of a second timeout between requests. (10 is 1/10th, 0 is not timeout)
    #
    def listener(options={},&blk)
      ops = resolve_defaults(options)
      ops[:num_processors] ||= 950
      ops[:timeout] ||= 0

      @listener = Mongrel::HttpServer.new(ops[:host], ops[:port].to_i, ops[:num_processors].to_i, ops[:timeout].to_i)
      @listener_name = "#{ops[:host]}:#{ops[:port]}"
      @listeners[@listener_name] = @listener
      
      if blk
        cloaker(&blk).bind(self).call
      end
      
      # all done processing this listener setup
      @listener = nil
      @listener_name = nil
    end
    
    
    # Called inside a Configurator.listener block in order to 
    # add URI->handler mappings for that listener.  Use this as
    # many times as you like.  It expects the following options
    # or defaults:
    #
    # * :handler => Handler to use for this location.
    def uri(location, options={})
      ops = resolve_defaults(options)
      @listener.register(location, ops[:handler], in_front=ops[:in_front])
    end
    
    
    # Daemonizes the current Ruby script turning all the
    # listeners into an actual "server" or detached process.
    # You must call this *before* frameworks that open files
    # as otherwise the files will be closed by this function.
    #
    # Does not work for Win32 systems (the call is silently ignored).
    #
    # Requires the following options or defaults:
    #
    # * :cwd => Directory to change to.
    # * :log_file => Where to write STDOUT and STDERR.
    # * :pid_file => Where to write the process ID.
    # 
    # It is safe to call this on win32 as it will only require daemons
    # if NOT win32.
    def daemonize(options={})
      ops = resolve_defaults(options)
      # save this for later since daemonize will hose it
      if RUBY_PLATFORM !~ /mswin/
        require 'daemons/daemonize'
        
        Daemonize.daemonize(log_file=File.join(ops[:cwd], ops[:log_file]))
        
        # change back to the original starting directory
        Dir.chdir(ops[:cwd])
        
        open(ops[:pid_file],"w") {|f| f.write(Process.pid) }
      else
        log "WARNING: Win32 does not support daemon mode."
      end
    end
    
    
    # Uses the GemPlugin system to easily load plugins based on their
    # gem dependencies.  You pass in either an :includes => [] or 
    # :excludes => [] setting listing the names of plugins to include
    # or exclude from the loading.
    def load_plugins(options={})
      ops = resolve_defaults(options)
      
      load_settings = {}
      if ops[:includes]
        ops[:includes].each do |plugin|
          load_settings[plugin] = GemPlugin::INCLUDE
        end
      end

      if ops[:excludes]
        ops[:excludes].each do |plugin|
          load_settings[plugin] = GemPlugin::EXCLUDE
        end
      end

      GemPlugin::Manager.instance.load(load_settings)
    end
    
    
    # Easy way to load a YAML file and apply default settings.
    def load_yaml(file, default={})
      default.merge(YAML.load_file(file))
    end
    
    
    # Loads the MIME map file and checks that it is correct
    # on loading.  This is commonly passed to Mongrel::DirHandler
    # or any framework handler that uses DirHandler to serve files.
    # You can also include a set of default MIME types as additional
    # settings.  See Mongrel::DirHandler for how the MIME types map
    # is organized.
    def load_mime_map(file, mime={})
      # configure any requested mime map
      mime = load_yaml(file, mime)
      
      # check all the mime types to make sure they are the right format
      mime.each {|k,v| log "WARNING: MIME type #{k} must start with '.'" if k.index(".") != 0 }
      
      return mime
    end
    
    
    # Loads and creates a plugin for you based on the given
    # name and configured with the selected options.  The options
    # are merged with the defaults prior to passing them in.
    def plugin(name, options={})
      ops = resolve_defaults(options)
      GemPlugin::Manager.instance.create(name, ops)
    end
    
    
    # Works like a meta run method which goes through all the 
    # configured listeners.  Use the Configurator.join method
    # to prevent Ruby from exiting until each one is done.
    def run
      @listeners.each {|name,s| 
        log "Running #{name} listener." 
        s.run 
      }
      
    end
    
    # Calls .stop on all the configured listeners so they
    # stop processing requests (gracefully).
    def stop
      @listeners.each {|name,s| 
        log "Stopping #{name} listener." 
        s.stop 
      }
    end


    # This method should actually be called *outside* of the
    # Configurator block so that you can control it.  In otherwords
    # do it like:  config.join.
    def join
      @listeners.values.each {|s| s.acceptor.join }
    end


    # Calling this before you register your URIs to the given location
    # will setup a set of handlers that log open files, objects, and the
    # parameters for each request.  This helps you track common problems
    # found in Rails applications that are either slow or become unresponsive
    # after a little while.
    def debug(location)
      require 'mongrel/debug'
      ObjectTracker.configure
      MongrelDbg.configure
      MongrelDbg.begin_trace :objects
      MongrelDbg.begin_trace :rails
      MongrelDbg.begin_trace :files
      MongrelDbg.begin_trace :threads
      
      uri location, :handler => plugin("/handlers/requestlog::access")
      uri location, :handler => plugin("/handlers/requestlog::files")
      uri location, :handler => plugin("/handlers/requestlog::objects")
      uri location, :handler => plugin("/handlers/requestlog::params")
      uri location, :handler => plugin("/handlers/requestlog::threads")
    end

    # Used to allow you to let users specify their own configurations
    # inside your Configurator setup.  You pass it a script name and
    # reads it in and does an eval on the contents passing in the right
    # binding so they can put their own Configurator statements.
    def run_config(script)
      open(script) {|f| eval(f.read, proc {self}) }
    end

    # Sets up the standard signal handlers that are used on most Ruby
    # It only configures if the platform is not win32 and doesn't do
    # a HUP signal since this is typically framework specific.
    #
    # Requires a :pid_file option to indicate a file to delete.  
    # It sets the MongrelConfig.needs_restart attribute if 
    # the start command should reload.  It's up to you to detect this
    # and do whatever is needed for a "restart".
    #
    # This command is safely ignored if the platform is win32 (with a warning)
    def setup_signals(options={})
      ops = resolve_defaults(options)
      
      if RUBY_PLATFORM !~ /mswin/
        # graceful shutdown
        trap("TERM") { 
          log "TERM signal received."
          stop 
          File.unlink ops[:pid_file] if File.exist?(ops[:pid_file])
        }
        
        # restart
        trap("USR2") { 
          log "USR2 signal received."
          stop
          File.unlink ops[:pid_file] if File.exist?(ops[:pid_file])
          @needs_restart = true
        }
        
        trap("INT") {
          log "INT signal received."
          stop
          File.unlink ops[:pid_file] if File.exist?(ops[:pid_file])
          @needs_restart = false
        }
        
        log "Signals ready.  TERM => stop.  USR2 => restart.  INT => stop (no restart)."
      else
        log "WARNING: Win32 does not have signals support."
      end
    end

    # Logs a simple message to STDERR (or the mongrel log if in daemon mode).
    def log(msg)
      STDERR.print "** ", msg, "\n"
    end
    
  end

end
