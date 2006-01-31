require 'socket'
require 'http11'
require 'thread'
require 'stringio'

# Mongrel module containing all of the classes (include C extensions) for running
# a Mongrel web server.  It contains a minimalist HTTP server with just enough
# functionality to service web application requests fast as possible.
module Mongrel

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

  # When a handler is found for a registered URI then this class is constructed
  # and passed to your HttpHandler::process method.  You should assume that 
  # *one* handler processes all requests.  Included in the HttpReqeust is a
  # HttpRequest.params Hash that matches common CGI params, and a HttpRequest.body
  # which is a string containing the request body (raw for now).
  #
  # Mongrel really only support small-ish request bodies right now since really
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
      params['CONTENT_LENGTH'] = params['HTTP_CONTENT_LENGTH'] || 0

      # now, if the initial_body isn't long enough for the content length we have to fill it
      # TODO: adapt for big ass stuff by writing to a temp file
      clen = params['HTTP_CONTENT_LENGTH'].to_i
      if @body.length < clen
        @body << @socket.read(clen - @body.length)
      end
    end
  end


  class HeaderOut
    attr_reader :out

    def initialize(out)
      @out = out
    end

    def[]=(key,value)
      @out.write(key)
      @out.write(": ")
      @out.write(value)
      @out.write("\r\n")
    end
  end


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

    def start(status=200)
      @status = status
      yield @header, @body
      finished
    end
    
    def finished
      @header.out.rewind
      @body.rewind
      
      # connection: close is also added to ensure that the client does not pipeline.
      @socket.write("HTTP/1.1 #{@status} #{HTTP_STATUS_CODES[@status]}\r\nContent-Length: #{@body.length}\r\nConnection: close\r\n")
      @socket.write(@header.out.read)
      @socket.write("\r\n")
      @socket.write(@body.read)
    end
  end
  

  # You implement your application handler with this.  It's very light giving
  # just the minimum necessary for you to handle a request and shoot back 
  # a response.  Look at the HttpRequest and HttpResponse objects for how
  # to use them.
  class HttpHandler
    attr_accessor :script_name

    def process(request, response)
    end
  end


  # The server normally returns a 404 response if a URI is requested, but it
  # also returns a lame empty message.  This lets you do a 404 response
  # with a custom message for special URIs.
  class Error404Handler < HttpHandler

    # Sets the message to return.  This is constructed once for the handler
    # so it's pretty efficient.
    def initialize(msg)
      @response = HttpServer::ERROR_404_RESPONSE + msg
    end
    
    # Just kicks back the standard 404 response with your special message.
    def process(request, response)
      response.socket.write(@response)
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

    # The standard empty 404 response for bad requests.  Use Error4040Handler for custom stuff.
    ERROR_404_RESPONSE="HTTP/1.1 404 Not Found\r\nConnection: close\r\nServer: Mongrel/0.2\r\n\r\nNOT FOUND"
    ERROR_503_RESPONSE="HTTP/1.1 503 Service Unavailable\r\n\r\nBUSY"

    # The basic max request size we'll try to read.
    CHUNK_SIZE=(16 * 1024)

    PATH_INFO="PATH_INFO"
    SCRIPT_NAME="SCRIPT_NAME"
    
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
    # Future versions of Mongrel will make this more dynamic (hopefully).
    def initialize(host, port, num_processors=20)
      @socket = TCPServer.new(host, port)
      @classifier = URIClassifier.new
      @req_queue = Queue.new
      num_processors.times {|i| Thread.new do
          while client = @req_queue.deq
            process_client(client)
          end
        end
      }
    end
    

    # Does the majority of the IO processing.  It has been written in Ruby using
    # about 7 different IO processing strategies and no matter how it's done 
    # the performance just does not improve.  Ruby's use of select to implement
    # threads means that it will most likely never improve, so the only remaining
    # approach is to write all or some of this function in C.  That will be the
    # focus of future releases.
    def process_client(client)
      begin
        parser = HttpParser.new
        params = {}
        data = client.readpartial(CHUNK_SIZE)

        while true
          nread = parser.execute(params, data)
          if parser.finished?
            script_name, path_info, handler = @classifier.resolve(params[PATH_INFO])

            if handler
              params[PATH_INFO] = path_info
              params[SCRIPT_NAME] = script_name

              request = HttpRequest.new(params, data[nread ... data.length], client)
              response = HttpResponse.new(client)
              handler.process(request, response)
            else
              client.write(ERROR_404_RESPONSE)
            end

            break
          else
            # gotta stream and read again until we can get the parser to be character safe
            # TODO: make this more efficient since this means we're parsing a lot repeatedly
            parser.reset
            data << client.readpartial(CHUNK_SIZE)
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
      @acceptor = Thread.new do
        while true
          @req_queue << @socket.accept
        end
      end
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
  end
end
