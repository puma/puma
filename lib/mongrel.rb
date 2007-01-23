# Copyright (c) 2005 Zed A. Shaw 
# You can redistribute it and/or modify it under the same terms as Ruby.
#
# Additional work donated by contributors.  See http://mongrel.rubyforge.org/attributions.html 
# for more information.

$mongrel_debug_client = false

require 'rubygems'
require 'socket'
require 'http11'
require 'tempfile'
begin
  require 'fastthread'
rescue RuntimeError => e
  warn "fastthread not loaded: #{ e.message }"
rescue LoadError
ensure
  require 'thread'
end
require 'stringio'
require 'mongrel/cgi'
require 'mongrel/handlers'
require 'mongrel/command'
require 'mongrel/tcphack'
require 'yaml'
require 'mongrel/configurator'
require 'time'
require 'etc'
require 'uri'


# Mongrel module containing all of the classes (include C extensions) for running
# a Mongrel web server.  It contains a minimalist HTTP server with just enough
# functionality to service web application requests fast as possible.
module Mongrel

  class URIClassifier
    attr_reader :handler_map

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
  class StopServer < Exception; end


  # Thrown at a thread when it is timed out.
  class TimeoutError < Exception; end


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

    # This is the initial part that your handler is identified as by URIClassifier.
    SCRIPT_NAME="SCRIPT_NAME".freeze

    # The original URI requested by the client.  Passed to URIClassifier to build PATH_INFO and SCRIPT_NAME.
    REQUEST_URI='REQUEST_URI'.freeze
    REQUEST_PATH='REQUEST_PATH'.freeze

    MONGREL_VERSION="1.0.1".freeze

    MONGREL_TMP_BASE="mongrel".freeze

    # The standard empty 404 response for bad requests.  Use Error4040Handler for custom stuff.
    ERROR_404_RESPONSE="HTTP/1.1 404 Not Found\r\nConnection: close\r\nServer: Mongrel #{MONGREL_VERSION}\r\n\r\nNOT FOUND".freeze

    CONTENT_LENGTH="CONTENT_LENGTH".freeze

    # A common header for indicating the server is too busy.  Not used yet.
    ERROR_503_RESPONSE="HTTP/1.1 503 Service Unavailable\r\n\r\nBUSY".freeze

    # The basic max request size we'll try to read.
    CHUNK_SIZE=(16 * 1024)

    # This is the maximum header that is allowed before a client is booted.  The parser detects
    # this, but we'd also like to do this as well.
    MAX_HEADER=1024 * (80 + 32)

    # Maximum request body size before it is moved out of memory and into a tempfile for reading.
    MAX_BODY=MAX_HEADER

    # A frozen format for this is about 15% faster
    STATUS_FORMAT = "HTTP/1.1 %d %s\r\nConnection: close\r\n".freeze
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
    HTTP_IF_MODIFIED_SINCE="HTTP_IF_MODIFIED_SINCE".freeze
    HTTP_IF_NONE_MATCH="HTTP_IF_NONE_MATCH".freeze
    REDIRECT = "HTTP/1.1 302 Found\r\nLocation: %s\r\nConnection: close\r\n\r\n".freeze
    HOST = "HOST".freeze
  end


  # Basically a Hash with one extra parameter for the HTTP body, mostly used internally.
  class HttpParams < Hash
    attr_accessor :http_body
  end


  # When a handler is found for a registered URI then this class is constructed
  # and passed to your HttpHandler::process method.  You should assume that 
  # *one* handler processes all requests.  Included in the HttpRequest is a
  # HttpRequest.params Hash that matches common CGI params, and a HttpRequest.body
  # which is a string containing the request body (raw for now).
  #
  # The HttpRequest.initialize method will convert any request that is larger than
  # Const::MAX_BODY into a Tempfile and use that as the body.  Otherwise it uses 
  # a StringIO object.  To be safe, you should assume it works like a file.
  #
  # The HttpHandler.request_notify system is implemented by having HttpRequest call
  # HttpHandler.request_begins, HttpHandler.request_progress, HttpHandler.process during
  # the IO processing.  This adds a small amount of overhead but lets you implement
  # finer controlled handlers and filters.
  class HttpRequest
    attr_reader :body, :params

    # You don't really call this.  It's made for you.
    # Main thing it does is hook up the params, and store any remaining
    # body data into the HttpRequest.body attribute.
    def initialize(params, socket, dispatchers)
      @params = params
      @socket = socket
      @dispatchers = dispatchers
      content_length = @params[Const::CONTENT_LENGTH].to_i
      remain = content_length - @params.http_body.length
      
      # tell all dispatchers the request has begun
      @dispatchers.each do |dispatcher|
        dispatcher.request_begins(@params) 
      end unless @dispatchers.nil? || @dispatchers.empty?

      # Some clients (like FF1.0) report 0 for body and then send a body.  This will probably truncate them but at least the request goes through usually.
      if remain <= 0
        # we've got everything, pack it up
        @body = StringIO.new
        @body.write @params.http_body
        update_request_progress(0, content_length)
      elsif remain > 0
        # must read more data to complete body
        if remain > Const::MAX_BODY
          # huge body, put it in a tempfile
          @body = Tempfile.new(Const::MONGREL_TMP_BASE)
          @body.binmode
        else
          # small body, just use that
          @body = StringIO.new 
        end

        @body.write @params.http_body
        read_body(remain, content_length)
      end

      @body.rewind if @body
    end

    # updates all dispatchers about our progress
    def update_request_progress(clen, total)
      return if @dispatchers.nil? || @dispatchers.empty?
      @dispatchers.each do |dispatcher|
        dispatcher.request_progress(@params, clen, total) 
      end 
    end
    private :update_request_progress

    # Does the heavy lifting of properly reading the larger body requests in 
    # small chunks.  It expects @body to be an IO object, @socket to be valid,
    # and will set @body = nil if the request fails.  It also expects any initial
    # part of the body that has been read to be in the @body already.
    def read_body(remain, total)
      begin
        # write the odd sized chunk first
        @params.http_body = read_socket(remain % Const::CHUNK_SIZE)

        remain -= @body.write(@params.http_body)

        update_request_progress(remain, total)

        # then stream out nothing but perfectly sized chunks
        until remain <= 0 or @socket.closed?
          # ASSUME: we are writing to a disk and these writes always write the requested amount
          @params.http_body = read_socket(Const::CHUNK_SIZE)
          remain -= @body.write(@params.http_body)

          update_request_progress(remain, total)
        end
      rescue Object
        STDERR.puts "ERROR reading http body: #$!"
        $!.backtrace.join("\n")
        # any errors means we should delete the file, including if the file is dumped
        @socket.close rescue Object
        @body.delete if @body.class == Tempfile
        @body = nil # signals that there was a problem
      end
    end
 
    def read_socket(len)
      if !@socket.closed?
        data = @socket.read(len)
        if !data
          raise "Socket read return nil"
        elsif data.length != len
          raise "Socket read returned insufficient data: #{data.length}"
        else
          data
        end
      else
        raise "Socket already closed when reading."
      end
    end

    # Performs URI escaping so that you can construct proper
    # query strings faster.  Use this rather than the cgi.rb
    # version since it's faster.  (Stolen from Camping).
    def self.escape(s)
      s.to_s.gsub(/([^ a-zA-Z0-9_.-]+)/n) {
        '%'+$1.unpack('H2'*$1.size).join('%').upcase
      }.tr(' ', '+') 
    end


    # Unescapes a URI escaped string. (Stolen from Camping).
    def self.unescape(s)
      s.tr('+', ' ').gsub(/((?:%[0-9a-fA-F]{2})+)/n){
        [$1.delete('%')].pack('H*')
      } 
    end

    # Parses a query string by breaking it up at the '&' 
    # and ';' characters.  You can also use this to parse
    # cookies by changing the characters used in the second
    # parameter (which defaults to '&;'.
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
    attr_accessor :allowed_duplicates

    def initialize(out)
      @sent = {}
      @allowed_duplicates = {"Set-Cookie" => true, "Set-Cookie2" => true,
        "Warning" => true, "WWW-Authenticate" => true}
      @out = out
    end

    # Simply writes "#{key}: #{value}" to an output buffer.
    def[]=(key,value)
      if not @sent.has_key?(key) or @allowed_duplicates.has_key?(key)
        @sent[key] = true
        @out.write(Const::HEADER_FORMAT % [key, value])
      end
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
    attr_writer :body
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
        @header.out.truncate(0)
        @body.close
        @body = StringIO.new
      end
    end

    def send_status(content_length=@body.length)
      if not @status_sent
        @header['Content-Length'] = content_length unless @status == 304
        write(Const::STATUS_FORMAT % [@status, HTTP_STATUS_CODES[@status]])
        @status_sent = true
      end
    end

    def send_header
      if not @header_sent
        @header.out.rewind
        write(@header.out.read + Const::LINE_END)
        @header_sent = true
      end
    end

    def send_body
      if not @body_sent
        @body.rewind
        write(@body.read)
        @body_sent = true
      end
    end 

    # Appends the contents of +path+ to the response stream.  The file is opened for binary
    # reading and written in chunks to the socket.
    #
    # Sendfile API support has been removed in 0.3.13.4 due to stability problems.
    def send_file(path, small_file = false)
      if small_file
        File.open(path, "rb") {|f| @socket << f.read }
      else
        File.open(path, "rb") do |f|
          while chunk = f.read(Const::CHUNK_SIZE) and chunk.length > 0
            begin
              write(chunk)
            rescue Object => exc
              break
            end
          end
        end
      end
      @body_sent = true
    end

    def socket_error(details)
      # ignore these since it means the client closed off early
      @socket.close rescue Object
      done = true
      raise details
    end

    def write(data)
      @socket.write(data)
    rescue => details
      socket_error(details)
    end

    # This takes whatever has been done to header and body and then writes it in the
    # proper format to make an HTTP/1.1 response.
    def finished
      send_status
      send_header
      send_body
    end

    # Used during error conditions to mark the response as "done" so there isn't any more processing
    # sent to the client.
    def done=(val)
      @status_sent = true
      @header_sent = true
      @body_sent = true
    end

    def done
      (@status_sent and @header_sent and @body_sent)
    end

  end


  # This is the main driver of Mongrel, while the Mongrel::HttpParser and Mongrel::URIClassifier
  # make up the majority of how the server functions.  It's a very simple class that just
  # has a thread accepting connections and a simple HttpServer.process_client function
  # to do the heavy lifting with the IO and Ruby.  
  #
  # You use it by doing the following:
  #
  #   server = HttpServer.new("0.0.0.0", 3000)
  #   server.register("/stuff", MyNiftyHandler.new)
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
    attr_reader :timeout
    attr_reader :num_processors

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
        params = HttpParams.new
        request = nil
        data = client.readpartial(Const::CHUNK_SIZE)
        nparsed = 0

        # Assumption: nparsed will always be less since data will get filled with more
        # after each parsing.  If it doesn't get more then there was a problem
        # with the read operation on the client socket.  Effect is to stop processing when the
        # socket can't fill the buffer for further parsing.
        while nparsed < data.length
          nparsed = parser.execute(params, data, nparsed)

          if parser.finished?
            if not params[Const::REQUEST_PATH]
              # it might be a dumbass full host request header
              uri = URI.parse(params[Const::REQUEST_URI])
              params[Const::REQUEST_PATH] = uri.request_uri
            end

            raise "No REQUEST PATH" if not params[Const::REQUEST_PATH]

            script_name, path_info, handlers = @classifier.resolve(params[Const::REQUEST_PATH])

            if handlers
              params[Const::PATH_INFO] = path_info
              params[Const::SCRIPT_NAME] = script_name
              params[Const::REMOTE_ADDR] = params[Const::HTTP_X_FORWARDED_FOR] || client.peeraddr.last

              # select handlers that want more detailed request notification
              notifiers = handlers.select { |h| h.request_notify }
              request = HttpRequest.new(params, client, notifiers)

              # in the case of large file uploads the user could close the socket, so skip those requests
              break if request.body == nil  # nil signals from HttpRequest::initialize that the request was aborted

              # request is good so far, continue processing the response
              response = HttpResponse.new(client)

              # Process each handler in registered order until we run out or one finalizes the response.
              handlers.each do |handler|
                handler.process(request, response)
                break if response.done or client.closed?
              end

              # And finally, if nobody closed the response off, we finalize it.
              unless response.done or client.closed? 
                response.finished
              end
            else
              # Didn't find it, return a stock 404 response.
              client.write(Const::ERROR_404_RESPONSE)
            end

            break #done
          else
            # Parser is not done, queue up more data to read and continue parsing
            chunk = client.readpartial(Const::CHUNK_SIZE)
            break if !chunk or chunk.length == 0  # read failed, stop processing

            data << chunk
            if data.length >= Const::MAX_HEADER
              raise HttpParserError.new("HEADER is longer than allowed, aborting client early.")
            end
          end
        end
      rescue EOFError,Errno::ECONNRESET,Errno::EPIPE,Errno::EINVAL,Errno::EBADF
        client.close rescue Object
      rescue HttpParserError
        if $mongrel_debug_client
          STDERR.puts "#{Time.now}: BAD CLIENT (#{params[Const::HTTP_X_FORWARDED_FOR] || client.peeraddr.last}): #$!"
          STDERR.puts "#{Time.now}: REQUEST DATA: #{data.inspect}\n---\nPARAMS: #{params.inspect}\n---\n"
        end
      rescue Errno::EMFILE
        reap_dead_workers('too many files')
      rescue Object
        STDERR.puts "#{Time.now}: ERROR: #$!"
        STDERR.puts $!.backtrace.join("\n") if $mongrel_debug_client
      ensure
        client.close rescue Object
        request.body.delete if request and request.body.class == Tempfile
      end
    end

    # Used internally to kill off any worker threads that have taken too long
    # to complete processing.  Only called if there are too many processors
    # currently servicing.  It returns the count of workers still active
    # after the reap is done.  It only runs if there are workers to reap.
    def reap_dead_workers(reason='unknown')
      if @workers.list.length > 0
        STDERR.puts "#{Time.now}: Reaping #{@workers.list.length} threads for slow workers because of '#{reason}'"
        error_msg = "Mongrel timed out this thread: #{reason}"
        mark = Time.now
        @workers.list.each do |w|
          w[:started_on] = Time.now if not w[:started_on]

          if mark - w[:started_on] > @death_time + @timeout
            STDERR.puts "Thread #{w.inspect} is too old, killing."
            w.raise(TimeoutError.new(error_msg))
          end
        end
      end

      return @workers.list.length
    end

    # Performs a wait on all the currently running threads and kills any that take
    # too long.  Right now it just waits 60 seconds, but will expand this to
    # allow setting.  The @timeout setting does extend this waiting period by
    # that much longer.
    def graceful_shutdown
      while reap_dead_workers("shutdown") > 0
        STDERR.print "Waiting for #{@workers.list.length} requests to finish, could take #{@death_time + @timeout} seconds."
        sleep @death_time / 10
      end
    end

    def configure_socket_options
      case RUBY_PLATFORM
      when /linux/
        # 9 is currently TCP_DEFER_ACCEPT
        $tcp_defer_accept_opts = [Socket::SOL_TCP, 9, 1]
        $tcp_cork_opts = [Socket::SOL_TCP, 3, 1]
      when /freebsd/
        # Use the HTTP accept filter if available.
        # The struct made by pack() is defined in /usr/include/sys/socket.h as accept_filter_arg
        unless `/sbin/sysctl -nq net.inet.accf.http`.empty?
          $tcp_defer_accept_opts = [Socket::SOL_SOCKET, Socket::SO_ACCEPTFILTER, ['httpready', nil].pack('a16a240')]
        end
      end
    end

    # Runs the thing.  It returns the thread used so you can "join" it.  You can also
    # access the HttpServer::acceptor attribute to get the thread later.
    def run
      BasicSocket.do_not_reverse_lookup=true

      configure_socket_options

      if $tcp_defer_accept_opts
        @socket.setsockopt(*$tcp_defer_accept_opts) rescue nil
      end

      @acceptor = Thread.new do
        while true
          begin
            client = @socket.accept

            if $tcp_cork_opts
              client.setsockopt(*$tcp_cork_opts) rescue nil
            end

            worker_list = @workers.list

            if worker_list.length >= @num_processors
              STDERR.puts "Server overloaded with #{worker_list.length} processors (#@num_processors max). Dropping connection."
              client.close rescue Object
              reap_dead_workers("max processors")
            else
              thread = Thread.new(client) {|c| process_client(c) }
              thread[:started_on] = Time.now
              @workers.add(thread)

              sleep @timeout/100 if @timeout > 0
            end
          rescue StopServer
            @socket.close rescue Object
            break
          rescue Errno::EMFILE
            reap_dead_workers("too many open files")
            sleep 0.5
          rescue Errno::ECONNABORTED
            # client closed the socket even before accept
            client.close rescue Object
          rescue Object => exc
            STDERR.puts "!!!!!! UNHANDLED EXCEPTION! #{exc}.  TELL ZED HE'S A MORON."
            STDERR.puts $!.backtrace.join("\n") if $mongrel_debug_client
          end
        end
        graceful_shutdown
      end

      return @acceptor
    end

    # Simply registers a handler with the internal URIClassifier.  When the URI is
    # found in the prefix of a request then your handler's HttpHandler::process method
    # is called.  See Mongrel::URIClassifier#register for more information.
    #
    # If you set in_front=true then the passed in handler will be put in front in the list.
    # Otherwise it's placed at the end of the list.
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

      handler.listener = self
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
end
