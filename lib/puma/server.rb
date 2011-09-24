require 'rack'
require 'puma/thread_pool'

module Puma
  class Server

    include Puma::Const

    attr_reader :acceptor
    attr_reader :host
    attr_reader :port
    attr_reader :concurrent

    attr_accessor :app

    attr_accessor :stderr, :stdout

    # Creates a working server on host:port (strange things happen if port
    # isn't a Number).
    #
    # Use HttpServer#run to start the server and HttpServer#acceptor.join to 
    # join the thread that's processing incoming requests on the socket.
    #
    # +concurrent+ indicates how many concurrent requests should be run at
    # the same time. Any requests over this ammount are queued and handled
    # as soon as a thread is available.
    #
    def initialize(host, port, concurrent=10)
      @socket = TCPServer.new(host, port) 
      
      @host = host
      @port = port
      @concurrent = concurrent

      @check, @notify = IO.pipe
      @running = true

      @thread_pool = ThreadPool.new(0, concurrent) do |client|
        process_client(client)
      end

      @stderr = STDERR
      @stdout = STDOUT
    end

    # Runs the server.  It returns the thread used so you can "join" it.
    # You can also access the HttpServer#acceptor attribute to get the
    # thread later.
    def run
      BasicSocket.do_not_reverse_lookup = true

      configure_socket_options

      if @tcp_defer_accept_opts
        @socket.setsockopt(*@tcp_defer_accept_opts)
      end

      tcp_cork_opts = @tcp_cork_opts

      @acceptor = Thread.new do
        begin
          check = @check
          sockets = [check, @socket]
          pool = @thread_pool

          while @running
            begin
              ios = IO.select sockets
              ios.first.each do |sock|
                if sock == check
                  break if handle_check
                else
                  client = sock.accept

                  client.setsockopt(*tcp_cork_opts) if tcp_cork_opts
     
                  pool << client
                end
              end
            rescue Errno::ECONNABORTED
              # client closed the socket even before accept
              client.close rescue nil
            rescue Object => e
              @stderr.puts "#{Time.now}: Unhandled listen loop exception #{e.inspect}."
              @stderr.puts e.backtrace.join("\n")
            end
          end
          graceful_shutdown
        ensure
          @socket.close
          # @stderr.puts "#{Time.now}: Closed socket."
        end
      end

      return @acceptor
    end

    def configure_socket_options
      @tcp_defer_accept_opts = nil
      @tcp_cork_opts = nil

      case RUBY_PLATFORM
      when /linux/
        # 9 is currently TCP_DEFER_ACCEPT
        @tcp_defer_accept_opts = [Socket::SOL_TCP, 9, 1]
        @tcp_cork_opts = [Socket::SOL_TCP, 3, 1]

      when /freebsd(([1-4]\..{1,2})|5\.[0-4])/
        # Do nothing, just closing a bug when freebsd <= 5.4
      when /freebsd/
        # Use the HTTP accept filter if available.
        # The struct made by pack() is defined in /usr/include/sys/socket.h as accept_filter_arg
        unless `/sbin/sysctl -nq net.inet.accf.http`.empty?
          @tcp_defer_accept_opts = [Socket::SOL_SOCKET, Socket::SO_ACCEPTFILTER, ['httpready', nil].pack('a16a240')]
        end
      end
    end



    def handle_check
      cmd = @check.read(1) 

      case cmd
      when STOP_COMMAND
        @running = false
        return true
      end

      return false
    end

    def process_client(client)
      begin
        parser = HttpParser.new
        params = {}
        data = client.readpartial(CHUNK_SIZE)
        nparsed = 0

        # Assumption: nparsed will always be less since data will get filled
        # with more after each parsing.  If it doesn't get more then there was
        # a problem with the read operation on the client socket. 
        # Effect is to stop processing when the socket can't fill the buffer
        # for further parsing.
        while nparsed < data.length
          nparsed = parser.execute(params, data, nparsed)

          if parser.finished?
            handle_request params, client, parser.body
            break
          else
            # Parser is not done, queue up more data to read and continue parsing
            chunk = client.readpartial(CHUNK_SIZE)
            break if !chunk or chunk.length == 0  # read failed, stop processing

            data << chunk
            if data.length >= MAX_HEADER
              raise HttpParserError,
                "HEADER is longer than allowed, aborting client early."
            end
          end
        end
      rescue EOFError, Errno::ECONNRESET, Errno::EPIPE, Errno::EINVAL,
             Errno::EBADF
        client.close rescue nil

      rescue HttpParserError => e
        @stderr.puts "#{Time.now}: HTTP parse error, malformed request (#{params[HTTP_X_FORWARDED_FOR] || client.peeraddr.last}): #{e.inspect}"
        @stderr.puts "#{Time.now}: REQUEST DATA: #{data.inspect}\n---\nPARAMS: #{params.inspect}\n---\n"

      rescue Object => e
        @stderr.puts "#{Time.now}: Read error: #{e.inspect}"
        @stderr.puts e.backtrace.join("\n")

      ensure
        begin
          client.close
        rescue IOError
          # Already closed
        rescue Object => e
          @stderr.puts "#{Time.now}: Client error: #{e.inspect}"
          @stderr.puts e.backtrace.join("\n")
        end
      end
    end

    def handle_request(params, client, body)
      if host = params[HTTP_HOST]
        if colon = host.index(":")
          params[SERVER_NAME] = host[0, colon]
          params[SERVER_PORT] = host[colon+1, host.size]
        else
          params[SERVER_NAME] = host
          params[SERVER_PORT] = PORT_80
        end
      end

      params[SERVER_PROTOCOL] = HTTP_11
      params[SERVER_SOFTWARE] = PUMA_VERSION
      params[GATEWAY_INTERFACE] = CGI_VER

      unless params[REQUEST_PATH]
        # it might be a dumbass full host request header
        uri = URI.parse(params[REQUEST_URI])
        params[REQUEST_PATH] = uri.path

        raise "No REQUEST PATH" unless params[REQUEST_PATH]
      end

      # From http://www.ietf.org/rfc/rfc3875 :
      # "Script authors should be aware that the REMOTE_ADDR and
      # REMOTE_HOST meta-variables (see sections 4.1.8 and 4.1.9)
      # may not identify the ultimate source of the request.
      # They identify the client for the immediate request to the
      # server; that client may be a proxy, gateway, or other
      # intermediary acting on behalf of the actual source client."
      #
      params[REMOTE_ADDR] = client.peeraddr.last

      process params, client, body
    end

    def process(env, client, body)

      body = read_body env, client, body

      return unless body

      begin
        env["SCRIPT_NAME"] = ""

        env["rack.version"] = Rack::VERSION
        env["rack.input"] = body
        env["rack.errors"] = $stderr
        env["rack.multithread"] = true
        env["rack.multiprocess"] = false
        env["rack.run_once"] = true
        env["rack.url_scheme"] =  env["HTTPS"] ? "https" : "http"

        env["CONTENT_TYPE"] ||= ""
        env["QUERY_STRING"] ||= ""

        status, headers, res_body = @app.call(env)

        client.write "HTTP/1.1 "
        client.write status.to_s
        client.write " "
        client.write HTTP_STATUS_CODES[status]
        client.write "\r\nConnection: close\r\n"

        colon = ": "
        line_ending = "\r\n"

        headers.each do |k, vs|
          vs.split("\n").each do |v|
            client.write k
            client.write colon
            client.write v
            client.write line_ending
          end
        end

        client.write line_ending

        if res_body.kind_of? String
          client.write body
          client.flush
        else
          res_body.each do |part|
            client.write part
            client.flush
          end
        end
      ensure
        body.close
        res_body.close if res_body.respond_to? :close
      end
    end

    def read_body(env, client, body)
      content_length = env[CONTENT_LENGTH].to_i

      remain = content_length - body.size

      return StringIO.new(body) if remain <= 0

      # Use a Tempfile if there is a lot of data left
      if remain > MAX_BODY
        stream = Tempfile.new(Const::PUMA_TMP_BASE)
        stream.binmode
      else
        stream = StringIO.new
      end

      stream.write body

      # Read an odd sized chunk so we can read even sized ones
      # after this
      chunk = client.readpartial(remain % CHUNK_SIZE)

      # No chunk means a closed socket
      unless chunk
        stream.close
        return nil
      end

      remain -= stream.write(chunk)

      # Raed the rest of the chunks
      while remain > 0
        chunk = client.readpartial(CHUNK_SIZE)
        unless chunk
          stream.close
          return nil
        end

        remain -= stream.write(chunk)
      end

      stream.rewind

      return stream
    end

    # Wait for all outstanding requests to finish.
    def graceful_shutdown
      @thread_pool.shutdown
    end

    # Stops the acceptor thread and then causes the worker threads to finish
    # off the request queue before finally exiting.
    def stop(sync=false)
      @notify << STOP_COMMAND

      @acceptor.join if sync
    end
  end

  HttpServer = Server
end
