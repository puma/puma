require 'rubygems'
require 'rack'
require 'stringio'

require 'puma/thread_pool'
require 'puma/const'
require 'puma/events'

require 'puma_http11'

require 'socket'

module Puma
  class Server

    include Puma::Const

    attr_reader :thread
    attr_reader :events
    attr_accessor :app

    attr_accessor :min_threads
    attr_accessor :max_threads
    attr_accessor :persistent_timeout

    # Creates a working server on host:port (strange things happen if port
    # isn't a Number).
    #
    # Use HttpServer#run to start the server and HttpServer#acceptor.join to 
    # join the thread that's processing incoming requests on the socket.
    #
    def initialize(app, events=Events::DEFAULT)
      @app = app
      @events = events

      @check, @notify = IO.pipe
      @ios = [@check]

      @running = false

      @min_threads = 0
      @max_threads = 16

      @thread = nil
      @thread_pool = nil

      @persistent_timeout = PERSISTENT_TIMEOUT

      @proto_env = {
        "rack.version".freeze => Rack::VERSION,
        "rack.errors".freeze => events.stderr,
        "rack.multithread".freeze => true,
        "rack.multiprocess".freeze => false,
        "rack.run_once".freeze => true,
        "SCRIPT_NAME".freeze => "",
        "CONTENT_TYPE".freeze => "",
        "QUERY_STRING".freeze => "",
        SERVER_PROTOCOL => HTTP_11,
        SERVER_SOFTWARE => PUMA_VERSION,
        GATEWAY_INTERFACE => CGI_VER
      }
    end

    if RUBY_PLATFORM =~ /linux/
      # 6 == Socket::IPPROTO_TCP
      # 3 == TCP_CORK
      # 1/0 == turn on/off
      def cork_socket(socket)
        socket.setsockopt(6, 3, 1) if socket.kind_of? TCPSocket
      end

      def uncork_socket(socket)
        socket.setsockopt(6, 3, 0) if socket.kind_of? TCPSocket
      end
    else
      def cork_socket(socket)
      end

      def uncork_socket(socket)
      end
    end

    def add_tcp_listener(host, port, optimize_for_latency=true)
      s = TCPServer.new(host, port)
      if optimize_for_latency
        s.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
      end
      @ios << s
    end

    def add_unix_listener(path)
      @ios << UNIXServer.new(path)
    end

    # Runs the server.  It returns the thread used so you can "join" it.
    # You can also access the HttpServer#acceptor attribute to get the
    # thread later.
    def run
      BasicSocket.do_not_reverse_lookup = true

      @running = true

      @thread_pool = ThreadPool.new(@min_threads, @max_threads) do |client|
        process_client(client)
      end

      @thread = Thread.new do
        begin
          check = @check
          sockets = @ios
          pool = @thread_pool

          while @running
            begin
              ios = IO.select sockets
              ios.first.each do |sock|
                if sock == check
                  break if handle_check
                else
                  pool << sock.accept
                end
              end
            rescue Errno::ECONNABORTED
              # client closed the socket even before accept
              client.close rescue nil
            rescue Object => e
              @events.unknown_error self, env, e, "Listen loop"
            end
          end
          graceful_shutdown
        ensure
          @ios.each { |i| i.close }
        end
      end

      return @thread
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
      parser = HttpParser.new

      begin
        while true
          parser.reset

          env = @proto_env.dup
          data = client.readpartial(CHUNK_SIZE)
          nparsed = 0

          # Assumption: nparsed will always be less since data will get filled
          # with more after each parsing.  If it doesn't get more then there was
          # a problem with the read operation on the client socket. 
          # Effect is to stop processing when the socket can't fill the buffer
          # for further parsing.
          while nparsed < data.length
            nparsed = parser.execute(env, data, nparsed)

            if parser.finished?
              cl = env[CONTENT_LENGTH]

              return unless handle_request(env, client, parser.body, cl)

              nparsed += parser.body.size if cl

              if data.size > nparsed
                data.slice!(0, nparsed)
                parser = HttpParser.new
                env = @proto_env.dup
                nparsed = 0
              else
                unless IO.select([client], nil, nil, @persistent_timeout)
                  raise EOFError, "Timed out persistent connection"
                end
              end
            else
              # Parser is not done, queue up more data to read and continue parsing
              chunk = client.readpartial(CHUNK_SIZE)
              return if !chunk or chunk.length == 0  # read failed, stop processing

              data << chunk
              if data.length >= MAX_HEADER
                raise HttpParserError,
                  "HEADER is longer than allowed, aborting client early."
              end
            end
          end
        end
      rescue EOFError, SystemCallError
        client.close rescue nil

      rescue HttpParserError => e
        @events.parse_error self, env, e

      rescue StandardError => e
        @events.unknown_error self, env, e, "Read"

      ensure
        begin
          client.close
        rescue IOError, SystemCallError
          # Already closed
        rescue StandardError => e
          @events.unknown_error self, env, e, "Client"
        end
      end
    end

    def normalize_env(env, client)
      if host = env[HTTP_HOST]
        if colon = host.index(":")
          env[SERVER_NAME] = host[0, colon]
          env[SERVER_PORT] = host[colon+1, host.size]
        else
          env[SERVER_NAME] = host
          env[SERVER_PORT] = PORT_80
        end
      end

      unless env[REQUEST_PATH]
        # it might be a dumbass full host request header
        uri = URI.parse(env[REQUEST_URI])
        env[REQUEST_PATH] = uri.path

        raise "No REQUEST PATH" unless env[REQUEST_PATH]
      end

      env[PATH_INFO] = env[REQUEST_PATH]

      # From http://www.ietf.org/rfc/rfc3875 :
      # "Script authors should be aware that the REMOTE_ADDR and
      # REMOTE_HOST meta-variables (see sections 4.1.8 and 4.1.9)
      # may not identify the ultimate source of the request.
      # They identify the client for the immediate request to the
      # server; that client may be a proxy, gateway, or other
      # intermediary acting on behalf of the actual source client."
      #
      env[REMOTE_ADDR] = client.peeraddr.last
    end

    EmptyBinary = ""
    EmptyBinary.force_encoding("BINARY") if EmptyBinary.respond_to? :force_encoding

    def handle_request(env, client, body, cl)
      normalize_env env, client

      if cl
        body = read_body env, client, body, cl
        return false unless body
      else
        body = StringIO.new(EmptyBinary)
      end

      env[RACK_INPUT] = body
      env[RACK_URL_SCHEME] =  env[HTTPS_KEY] ? HTTPS : HTTP

      after_reply = env[RACK_AFTER_REPLY] = []

      begin
        begin
          status, headers, res_body = @app.call(env)
        rescue => e
          status, headers, res_body = lowlevel_error(e)
        end

        content_length = nil

        if res_body.kind_of? Array and res_body.size == 1
          content_length = res_body[0].size
        end

        cork_socket client

        if env[HTTP_VERSION] == HTTP_11
          allow_chunked = true
          keep_alive = env[HTTP_CONNECTION] != CLOSE
          include_keepalive_header = false

          if status == 200
            client.write HTTP_11_200
          else
            client.write "HTTP/1.1 "
            client.write status.to_s
            client.write " "
            client.write HTTP_STATUS_CODES[status]
            client.write "\r\n"
          end
        else
          allow_chunked = false
          keep_alive = env[HTTP_CONNECTION] == KEEP_ALIVE
          include_keepalive_header = keep_alive

          if status == 200
            client.write HTTP_10_200
          else
            client.write "HTTP/1.1 "
            client.write status.to_s
            client.write " "
            client.write HTTP_STATUS_CODES[status]
            client.write "\r\n"
          end
        end

        colon = COLON
        line_ending = LINE_END

        headers.each do |k, vs|
          case k
          when CONTENT_LENGTH2
            content_length = vs
            next
          when TRANSFER_ENCODING
            allow_chunked = false
            content_length = nil
          end

          vs.split(NEWLINE).each do |v|
            client.write k
            client.write colon
            client.write v
            client.write line_ending
          end
        end

        if include_keepalive_header
          client.write CONNECTION_KEEP_ALIVE
        elsif !keep_alive
          client.write CONNECTION_CLOSE
        end

        if content_length
          client.write CONTENT_LENGTH_S
          client.write content_length.to_s
          client.write line_ending
          chunked = false
        elsif allow_chunked
          client.write TRANSFER_ENCODING_CHUNKED
          chunked = true
        end

        client.write line_ending

        res_body.each do |part|
          if chunked
            client.write part.size.to_s(16)
            client.write line_ending
            client.write part
            client.write line_ending
          else
            client.write part
          end

          client.flush
        end

        if chunked
          client.write CLOSE_CHUNKED
          client.flush
        end

      ensure
        uncork_socket client

        body.close
        res_body.close if res_body.respond_to? :close

        after_reply.each { |o| o.call }
      end

      return keep_alive
    end

    def read_body(env, client, body, cl)
      content_length = cl.to_i

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

    def lowlevel_error(e)
      [500, {}, ["No application configured"]]
    end

    # Wait for all outstanding requests to finish.
    def graceful_shutdown
      @thread_pool.shutdown if @thread_pool
    end

    # Stops the acceptor thread and then causes the worker threads to finish
    # off the request queue before finally exiting.
    def stop(sync=false)
      @notify << STOP_COMMAND

      @thread.join if @thread && sync
    end

    def attempt_bonjour(name)
      begin
        require 'dnssd'
      rescue LoadError
        return false
      end

      @bonjour_registered = false
      announced = false

      @ios.each do |io|
        if io.kind_of? TCPServer
          fixed_name = name.gsub(/\./, "-")

          DNSSD.announce io, "puma - #{fixed_name}", "http" do |r|
            @bonjour_registered = true
          end

          announced = true
        end
      end

      return announced
    end

    def bonjour_registered?
      @bonjour_registered ||= false
    end
  end
end
