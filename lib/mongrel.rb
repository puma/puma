require 'socket'
require 'http11'
require 'thread'
require 'stringio'
require 'mongrel/cgi'
require 'mongrel/handlers'
require 'mongrel/command'
require 'timeout'
require 'mongrel/tcphack'


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

  # Used to timeout worker threads that have taken too long
  class TimeoutWorker < Exception
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
    # This is the part of the path after the SCRIPT_NAME.  URIClassifier will determine this.
    PATH_INFO="PATH_INFO"
    # This is the intial part that your handler is identified as by URIClassifier.
    SCRIPT_NAME="SCRIPT_NAME"
    # The original URI requested by the client.  Passed to URIClassifier to build PATH_INFO and SCRIPT_NAME.
    REQUEST_URI='REQUEST_URI'

    # Content length (also available as HTTP_CONTENT_LENGTH).
    CONTENT_LENGTH='CONTENT_LENGTH'

    # Content length (also available as CONTENT_LENGTH).
    HTTP_CONTENT_LENGTH='HTTP_CONTENT_LENGTH'

    # Content type (also available as HTTP_CONTENT_TYPE).
    CONTENT_TYPE='CONTENT_TYPE'

    # Content type (also available as CONTENT_TYPE).
    HTTP_CONTENT_TYPE='HTTP_CONTENT_TYPE'

    # Gateway interface key in the HttpRequest parameters.
    GATEWAY_INTERFACE='GATEWAY_INTERFACE'
    # We claim to support CGI/1.2.
    GATEWAY_INTERFACE_VALUE='CGI/1.2'

    # Hosts remote IP address.  Mongrel does not do DNS resolves since that slows 
    # processing down considerably.
    REMOTE_ADDR='REMOTE_ADDR'

    # This is not given since Mongrel does not do DNS resolves.  It is only here for
    # completeness for the CGI standard.
    REMOTE_HOST='REMOTE_HOST'

    # The name/host of our server as given by the HttpServer.new(host,port) call.
    SERVER_NAME='SERVER_NAME'

    # The port of our server as given by the HttpServer.new(host,port) call.
    SERVER_PORT='SERVER_PORT'

    # SERVER_NAME and SERVER_PORT come from this.
    HTTP_HOST='HTTP_HOST'

    # Official server protocol key in the HttpRequest parameters.
    SERVER_PROTOCOL='SERVER_PROTOCOL'
    # Mongrel claims to support HTTP/1.1.
    SERVER_PROTOCOL_VALUE='HTTP/1.1'

    # The actual server software being used (it's Mongrel man).
    SERVER_SOFTWARE='SERVER_SOFTWARE'
    
    # Current Mongrel version (used for SERVER_SOFTWARE and other response headers).
    MONGREL_VERSION='Mongrel 0.3.10'

    # The standard empty 404 response for bad requests.  Use Error4040Handler for custom stuff.
    ERROR_404_RESPONSE="HTTP/1.1 404 Not Found\r\nConnection: close\r\nServer: #{MONGREL_VERSION}\r\n\r\nNOT FOUND"

    # A common header for indicating the server is too busy.  Not used yet.
    ERROR_503_RESPONSE="HTTP/1.1 503 Service Unavailable\r\n\r\nBUSY"

    # The basic max request size we'll try to read.
    CHUNK_SIZE=(16 * 1024)

  end


  # When a handler is found for a registered URI then this class is constructed
  # and passed to your HttpHandler::process method.  You should assume that 
  # *one* handler processes all requests.  Included in the HttpReqeust is a
  # HttpRequest.params Hash that matches common CGI params, and a HttpRequest.body
  # which is a string containing the request body (raw for now).
  #
  # Mongrel really only supports small-ish request bodies right now since really
  # huge ones have to be completely read off the wire and put into a string.
  # Later there will be several options for efficiently handling large file
  # uploads.
  class HttpRequest
    attr_reader :body, :params

    # You don't really call this.  It's made for you.
    # Main thing it does is hook up the params, and store any remaining
    # body data into the HttpRequest.body attribute.
    def initialize(params, initial_body, socket)
      @body = initial_body || ""
      @params = params
      @socket = socket
      
      # fix up the CGI requirements
      params[Const::CONTENT_LENGTH] = params[Const::HTTP_CONTENT_LENGTH] || 0
      params[Const::CONTENT_TYPE] = params[Const::HTTP_CONTENT_TYPE] if params[Const::HTTP_CONTENT_TYPE]
      params[Const::GATEWAY_INTERFACE]=Const::GATEWAY_INTERFACE_VALUE
      params[Const::REMOTE_ADDR]=socket.peeraddr[3]
      host,port = params[Const::HTTP_HOST].split(":")
      params[Const::SERVER_NAME]=host
      params[Const::SERVER_PORT]=port || 80
      params[Const::SERVER_PROTOCOL]=Const::SERVER_PROTOCOL_VALUE
      params[Const::SERVER_SOFTWARE]=Const::MONGREL_VERSION


      # now, if the initial_body isn't long enough for the content length we have to fill it
      # TODO: adapt for big ass stuff by writing to a temp file
      clen = params[Const::HTTP_CONTENT_LENGTH].to_i
      if @body.length < clen
        @body << @socket.read(clen - @body.length)
      end
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
      @out.write(key)
      @out.write(": ")
      @out.write(value)
      @out.write("\r\n")
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
    
    def initialize(socket)
      @socket = socket
      @body = StringIO.new
      @status = 404
      @header = HeaderOut.new(StringIO.new)
    end

    # Receives a block passing it the header and body for you to work with.
    # When the block is finished it writes everything you've done to 
    # the socket in the proper order.  This lets you intermix header and
    # body content as needed.
    def start(status=200)
      @status = status.to_i
      yield @header, @body
      finished
    end

    # Primarily used in exception handling to reset the response output in order to write
    # an alternative response.
    def reset
      @header.out.rewind
      @body.rewind
    end

    def send_status
      status = "HTTP/1.1 #{@status} #{HTTP_STATUS_CODES[@status]}\r\nContent-Length: #{@body.length}\r\nConnection: close\r\n"
      @socket.write(status)
    end

    def send_header
      @header.out.rewind
      @socket.write(@header.out.read)
      @socket.write("\r\n")
    end

    def send_body
      @body.rewind
      # connection: close is also added to ensure that the client does not pipeline.
      @socket.write(@body.read)
    end 

    # This takes whatever has been done to header and body and then writes it in the
    # proper format to make an HTTP/1.1 response.
    def finished
      send_status
      send_header
      send_body
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

    # Creates a working server on host:port (strange things happen if port isn't a Number).
    # Use HttpServer::run to start the server.
    #
    # The num_processors variable has varying affects on how requests are processed.  You'd
    # think adding more processing threads (processors) would make the server faster, but
    # that's just not true.  There's actually an effect of how Ruby does threads such that
    # the more processors waiting on the request queue, the slower the system is to handle
    # each request.  But, the lower the number of processors the fewer concurrent responses
    # the server can make.
    #
    # 20 is the default number of processors and is based on experimentation on a few
    # systems.  If you find that you overload Mongrel too much
    # try changing it higher.  If you find that responses are way too slow
    # try lowering it (after you've tuned your stuff of course).
    def initialize(host, port, num_processors=20, timeout=120)
      @socket = TCPServer.new(host, port) 

      @classifier = URIClassifier.new
      @req_queue = Queue.new
      @host = host
      @port = port
      @processors = []

      # create the worker threads
      num_processors.times do |i| 
        @processors << Thread.new do
          while client = @req_queue.deq
            Timeout::timeout(timeout) do
              process_client(client)
            end
          end
        end
      end

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
            script_name, path_info, handler = @classifier.resolve(params[Const::REQUEST_URI])

            if handler
              params[Const::PATH_INFO] = path_info
              params[Const::SCRIPT_NAME] = script_name
              request = HttpRequest.new(params, data[nread ... data.length], client)
              response = HttpResponse.new(client)
              handler.process(request, response)
            else
              client.write(Const::ERROR_404_RESPONSE)
            end
            
            break #done
          else
            # gotta stream and read again until we can get the parser to be character safe
            # TODO: make this more efficient since this means we're parsing a lot repeatedly
            parser.reset
            data << client.readpartial(Const::CHUNK_SIZE)
          end
        end
      rescue EOFError
        # ignored
      rescue Errno::ECONNRESET
        # ignored
      rescue Errno::EPIPE
        # ignored
      rescue => details
        STDERR.puts "ERROR(#{details.class}): #{details}"
        STDERR.puts details.backtrace.join("\n")
      ensure
        client.close
      end
    end

    # Runs the thing.  It returns the thread used so you can "join" it.  You can also
    # access the HttpServer::acceptor attribute to get the thread later.
    def run
      BasicSocket.do_not_reverse_lookup=true
      @acceptor = Thread.new do
        Thread.current[:stopped] = false

        while not Thread.current[:stopped]
          begin
            @req_queue << @socket.accept
          rescue StopServer
            STDERR.puts "Server stopped.  Exiting."
            @socket.close if not @socket.closed?
            break
          rescue Errno::EMFILE
            STDERR.puts "Too many open files.  Try increasing ulimits."
            sleep 0.5
          end
        end

        # now that processing is done we feed enough false onto the request queue to get
        # each processor to exit and stop processing.
        @processors.length.times { @req_queue << false }

        # finally we wait until the queue is empty
        while @req_queue.length > 0
          STDERR.puts "Shutdown waiting for #{@req_queue.length} requests" if @req_queue.length > 0
          sleep 1
        end
      end

      @acceptor.priority = 1

      return @acceptor
    end

    
    # Simply registers a handler with the internal URIClassifier.  When the URI is
    # found in the prefix of a request then your handler's HttpHandler::process method
    # is called.  See Mongrel::URIClassifier#register for more information.
    def register(uri, handler)
      @classifier.register(uri, handler)
    end

    # Removes any handler registered at the given URI.  See Mongrel::URIClassifier#unregister
    # for more information.
    def unregister(uri)
      @classifier.unregister(uri)
    end

    # Stops the acceptor thread and then causes the worker threads to finish
    # off the request queue before finally exiting.
    def stop
      stopper = Thread.new do 
        @acceptor[:stopped] = true
        exc = StopServer.new
        @acceptor.raise(exc)
      end
      stopper.priority = 10
    end

  end

end
