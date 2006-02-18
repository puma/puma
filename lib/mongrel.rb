require 'socket'
require 'http11'
require 'thread'
require 'stringio'
require 'timeout'
require 'cgi'


# Mongrel module containing all of the classes (include C extensions) for running
# a Mongrel web server.  It contains a minimalist HTTP server with just enough
# functionality to service web application requests fast as possible.
module Mongrel

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

    # Official server protocol key in the HttpRequest parameters.
    SERVER_PROTOCOL='SERVER_PROTOCOL'
    # Mongrel claims to support HTTP/1.1.
    SERVER_PROTOCOL_VALUE='HTTP/1.1'

    # The actual server software being used (it's Mongrel man).
    SERVER_SOFTWARE='SERVER_SOFTWARE'
    
    # Current Mongrel version (used for SERVER_SOFTWARE and other response headers).
    MONGREL_VERSION='Mongrel 0.3.4'

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
      params[Const::CONTENT_TYPE] ||= params[Const::HTTP_CONTENT_TYPE]

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
  

  # You implement your application handler with this.  It's very light giving
  # just the minimum necessary for you to handle a request and shoot back 
  # a response.  Look at the HttpRequest and HttpResponse objects for how
  # to use them.
  class HttpHandler
    def process(request, response)
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
    # Future versions of Mongrel will make this more dynamic (hopefully).
    def initialize(host, port, num_processors=20, timeout=120)
      @socket = TCPServer.new(host, port)

      @classifier = URIClassifier.new
      @req_queue = Queue.new
      @host = host
      @port = port
      @num_processors = num_processors
      @timeout = timeout

      @num_processors.times {|i| Thread.new do
          while client = @req_queue.deq
            begin
              Timeout.timeout(@timeout) do
                process_client(client)
              end
            rescue Timeout::Error
              STDERR.puts "WARNING: Request took longer than #@timeout second timeout"
            end
          end
        end
      }
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
              params[Const::GATEWAY_INTERFACE]=Const::GATEWAY_INTERFACE_VALUE
              params[Const::REMOTE_ADDR]=client.peeraddr[3]
              params[Const::SERVER_NAME]=@host
              params[Const::SERVER_PORT]=@port
              params[Const::SERVER_PROTOCOL]=Const::SERVER_PROTOCOL_VALUE
              params[Const::SERVER_SOFTWARE]=Const::MONGREL_VERSION

              request = HttpRequest.new(params, data[nread ... data.length], client)
              response = HttpResponse.new(client)
              handler.process(request, response)
            else
              client.write(Const::ERROR_404_RESPONSE)
            end

            break
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


  # The server normally returns a 404 response if a URI is requested, but it
  # also returns a lame empty message.  This lets you do a 404 response
  # with a custom message for special URIs.
  class Error404Handler < HttpHandler

    # Sets the message to return.  This is constructed once for the handler
    # so it's pretty efficient.
    def initialize(msg)
      @response = Const::ERROR_404_RESPONSE + msg
    end
    
    # Just kicks back the standard 404 response with your special message.
    def process(request, response)
      response.socket.write(@response)
    end

  end


  # Serves the contents of a directory.  You give it the path to the root
  # where the files are located, and it tries to find the files based on 
  # the PATH_INFO inside the directory.  If the requested path is a
  # directory then it returns a simple directory listing.
  #
  # It does a simple protection against going outside it's root path by
  # converting all paths to an absolute expanded path, and then making sure
  # that the final expanded path includes the root path.  If it doesn't
  # than it simply gives a 404.
  class DirHandler < HttpHandler
    MIME_TYPES = {
      ".css"        =>  "text/css",
      ".gif"        =>  "image/gif",
      ".htm"        =>  "text/html",
      ".html"       =>  "text/html",
      ".jpeg"       =>  "image/jpeg",
      ".jpg"        =>  "image/jpeg",
      ".js"         =>  "text/javascript",
      ".png"        =>  "image/png",
      ".swf"        =>  "application/x-shockwave-flash",
      ".txt"        =>  "text/plain"
    }


    attr_reader :path

    # You give it the path to the directory root and an (optional) 
    def initialize(path, listing_allowed=true, index_html="index.html")
      @path = File.expand_path(path)
      @listing_allowed=listing_allowed
      @index_html = index_html
    end

    # Checks if the given path can be served and returns the full path (or nil if not).
    def can_serve(path_info)
      req = File.expand_path(File.join(@path,path_info), @path)

      if req.index(@path) == 0 and File.exist? req
        # it exists and it's in the right location
        if File.directory? req
          # the request is for a directory
          index = File.join(req, @index_html)
          if File.exist? index
            # serve the index
            return index
          elsif @listing_allows
            # serve the directory
            req
          else
            # do not serve anything
            return nil
          end
        else
          # it's a file and it's there
          return req
        end
      else
        # does not exist or isn't in the right spot
        return nil
      end
    end


    # Returns a simplistic directory listing if they're enabled, otherwise a 403.
    # Base is the base URI from the REQUEST_URI, dir is the directory to serve 
    # on the file system (comes from can_serve()), and response is the HttpResponse
    # object to send the results on.
    def send_dir_listing(base, dir, response)
      # take off any trailing / so the links come out right
      base.chop! if base[-1] == "/"[-1]

      if @listing_allowed
        response.start(200) do |head,out|
          head['Content-Type'] = "text/html"
          out << "<html><head><title>Directory Listing</title></head><body>"
          Dir.entries(dir).each do |child|
            next if child == "."

            if child == ".."
              out << "<a href=\"#{base}/#{child}\">Up to parent..</a><br/>"
            else
              out << "<a href=\"#{base}/#{child}\">#{child}</a><br/>"
            end
          end
          out << "</body></html>"
        end
      else
        response.start(403) do |head,out|
          out.write("Directory listings not allowed")
        end
      end
    end

    
    # Sends the contents of a file back to the user. Not terribly efficient since it's
    # opening and closing the file for each read.
    def send_file(req, response)
      response.start(200) do |head,out|
        # set the mime type from our map based on the ending
        dot_at = req.rindex(".")
        if dot_at
          ext = req[dot_at .. -1]
          if MIME_TYPES[ext]
            head['Content-Type'] = MIME_TYPES[ext]
          end
        end

        open(req, "rb") do |f|
          out.write(f.read)
        end
      end
    end


    # Process the request to either serve a file or a directory listing
    # if allowed (based on the listing_allowed paramter to the constructor).
    def process(request, response)
      req = can_serve request.params['PATH_INFO']
      if not req
        # not found, return a 404
        response.start(404) do |head,out|
          out << "File not found"
        end
      else
        begin
          if File.directory? req
            send_dir_listing(request.params["REQUEST_URI"],req, response)
          else
            send_file(req, response)
          end
        rescue => details
          response.reset
          response.start(403) do |head,out|
            out << "Error accessing file: #{details}"
            out << details.backtrace.join("\n")
          end
        end
      end
    end

    # There is a small number of default mime types for extensions, but
    # this lets you add any others you'll need when serving content.
    def DirHandler::add_mime_type(extension, type)
      MIME_TYPES[extension] = type
    end

  end


  # The beginning of a complete wrapper around Mongrel's internal HTTP processing
  # system but maintaining the original Ruby CGI module.  Use this only as a crutch
  # to get existing CGI based systems working.  It should handle everything, but please
  # notify me if you see special warnings.  This work is still very alpha so I need 
  # testers to help work out the various corner cases.
  class CGIWrapper < ::CGI
    public :env_table
    attr_reader :options

    # these are stripped out of any keys passed to CGIWrapper.header function
    REMOVED_KEYS = [ "nph","status","server","connection","type",
                     "charset","length","language","expires"]

    def initialize(request, response, *args)
      @request = request
      @response = response
      @args = *args
      @input = StringIO.new(request.body)
      @head = {}
      @out_called = false
      super(*args)
    end
    
    # The header is typically called to send back the header.  In our case we
    # collect it into a hash for later usage.
    #
    # nph -- Mostly ignored.  It'll output the date.
    # connection -- Completely ignored.  Why is CGI doing this?
    # length -- Ignored since Mongrel figures this out from what you write to output.
    # 
    def header(options = "text/html")
      
      # if they pass in a string then just write the Content-Type
      if options.class == String
        @head['Content-Type'] = options
      else
        # convert the given options into what Mongrel wants
        @head['Content-Type'] = options['type'] || "text/html"
        @head['Content-Type'] += "; charset=" + options['charset'] if options.has_key? "charset" if options['charset']
        
        # setup date only if they use nph
        @head['Date'] = CGI::rfc1123_date(Time.now) if options['nph']

        # setup the server to use the default or what they set
        @head['Server'] = options['server'] || env_table['SERVER_SOFTWARE']

        # remaining possible options they can give
        @head['Status'] = options['status'] if options['status']
        @head['Content-Language'] = options['language'] if options['language']
        @head['Expires'] = options['expires'] if options['expires']

        # drop the keys we don't want anymore
        REMOVED_KEYS.each {|k| options.delete(k) }

        # finally just convert the rest raw (which puts 'cookie' directly)
        # 'cookie' is translated later as we write the header out
        options.each{|k,v| @head[k] = v}
      end

      # doing this fakes out the cgi library to think the headers are empty
      # we then do the real headers in the out function call later
      ""
    end

    # Takes any 'cookie' setting and sends it over the Mongrel header,
    # then removes the setting from the options. If cookie is an 
    # Array or Hash then it sends those on with .to_s, otherwise
    # it just calls .to_s on it and hopefully your "cookie" can
    # write itself correctly.
    def send_cookies(to)
      # convert the cookies based on the myriad of possible ways to set a cookie
      if @head['cookie']
        cookie = @head['cookie']
        case cookie
        when Array
          cookie.each {|c| to['Set-Cookie'] = c.to_s }
        when Hash
          cookie.each_value {|c| to['Set-Cookie'] = c.to_s}
        else
          to['Set-Cookie'] = options['cookie'].to_s
        end
        
        @head.delete('cookie')

        # @output_cookies seems to never be used, but we'll process it just in case
        @output_cookies.each {|c| to['Set-Cookie'] = c.to_s } if @output_cookies
      end
    end
    
    # The dumb thing is people can call header or this or both and in any order.
    # So, we just reuse header and then finalize the HttpResponse the right way.
    # Status is taken from the various options and converted to what Mongrel needs
    # via the CGIWrapper.status function.
    def out(options = "text/html")
      return if @out_called  # don't do this more than once

      header(options)

      @response.start status do |head, out|
        send_cookies(head)
        
        @head.each {|k,v| head[k] = v}
        out.write(yield || "")
      end
    end
    
    # Computes the status once, but lazily so that people who call header twice
    # don't get penalized.  Because CGI insists on including the options status 
    # message in the status we have to do a bit of parsing.
    def status
      if not @status
        @status = @head["Status"] || @head["status"]
        
        if @status
          @status[0 ... @status.index(' ')] || "200"
        else
          @status = "200"
        end
      end
    end
    
    # Used to wrap the normal args variable used inside CGI.
    def args
      @args
    end
    
    # Used to wrap the normal env_table variable used inside CGI.
    def env_table
      @request.params
    end
    
    # Used to wrap the normal stdinput variable used inside CGI.
    def stdinput
      @input
    end
    
    # The stdoutput should be completely bypassed but we'll drop a warning just in case
    def stdoutput
      STDERR.puts "WARNING: Your program is doing something not expected.  Please tell Zed that stdoutput was used and what software you are running.  Thanks."
      @response.body
    end    
  end

end
