require 'rack'
require 'stringio'

require 'puma/thread_pool'
require 'puma/const'
require 'puma/events'
require 'puma/null_io'
require 'puma/compat'

require 'puma/puma_http11'

require 'socket'

module Puma

  # The HTTP Server itself. Serves out a single Rack app.
  class Server

    include Puma::Const

    attr_reader :thread
    attr_reader :events
    attr_accessor :app

    attr_accessor :min_threads
    attr_accessor :max_threads
    attr_accessor :persistent_timeout
    attr_accessor :auto_trim_time

    # Create a server for the rack app +app+.
    #
    # +events+ is an object which will be called when certain error events occur
    # to be handled. See Puma::Events for the list of current methods to implement.
    #
    # Server#run returns a thread that you can join on to wait for the server
    # to do it's work.
    #
    def initialize(app, events=Events::DEFAULT)
      @app = app
      @events = events

      @check, @notify = IO.pipe
      @ios = [@check]

      @status = :stop

      @min_threads = 0
      @max_threads = 16
      @auto_trim_time = 1

      @thread = nil
      @thread_pool = nil

      @persistent_timeout = PERSISTENT_TIMEOUT
      @persistent_check, @persistent_wakeup = IO.pipe

      @unix_paths = []

      @proto_env = {
        "rack.version".freeze => Rack::VERSION,
        "rack.errors".freeze => events.stderr,
        "rack.multithread".freeze => true,
        "rack.multiprocess".freeze => false,
        "rack.run_once".freeze => true,
        "SCRIPT_NAME".freeze => "",

        # Rack blows up if this is an empty string, and Rack::Lint
        # blows up if it's nil. So 'text/plain' seems like the most
        # sensible default value.
        "CONTENT_TYPE".freeze => "text/plain",

        "QUERY_STRING".freeze => "",
        SERVER_PROTOCOL => HTTP_11,
        SERVER_SOFTWARE => PUMA_VERSION,
        GATEWAY_INTERFACE => CGI_VER
      }

      @envs = {}

      ENV['RACK_ENV'] ||= "development"
    end

    # On Linux, use TCP_CORK to better control how the TCP stack
    # packetizes our stream. This improves both latency and throughput.
    #
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

    # Tell the server to listen on host +host+, port +port+.
    # If +optimize_for_latency+ is true (the default) then clients connecting
    # will be optimized for latency over throughput.
    #
    # +backlog+ indicates how many unaccepted connections the kernel should
    # allow to accumulate before returning connection refused.
    #
    def add_tcp_listener(host, port, optimize_for_latency=true, backlog=1024)
      s = TCPServer.new(host, port)
      if optimize_for_latency
        s.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
      end
      s.setsockopt(Socket::SOL_SOCKET,Socket::SO_REUSEADDR, true)
      s.listen backlog
      @ios << s
      s
    end

    def inherit_tcp_listener(host, port, fd)
      s = TCPServer.for_fd(fd)
      @ios << s
      s
    end

    def add_ssl_listener(host, port, ctx, optimize_for_latency=true, backlog=1024)
      s = TCPServer.new(host, port)
      if optimize_for_latency
        s.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
      end
      s.setsockopt(Socket::SOL_SOCKET,Socket::SO_REUSEADDR, true)
      s.listen backlog

      ssl = OpenSSL::SSL::SSLServer.new(s, ctx)
      env = @proto_env.dup
      env[HTTPS_KEY] = HTTPS
      @envs[ssl] = env

      @ios << ssl
      s
    end

    def inherited_ssl_listener(fd, ctx)
      s = TCPServer.for_fd(fd)
      @ios << OpenSSL::SSL::SSLServer.new(s, ctx)
      s
    end

    # Tell the server to listen on +path+ as a UNIX domain socket.
    #
    def add_unix_listener(path, umask=nil)
      @unix_paths << path

      # Let anyone connect by default
      umask ||= 0

      begin
        old_mask = File.umask(umask)
        s = UNIXServer.new(path)
        @ios << s
      ensure
        File.umask old_mask
      end

      s
    end

    def inherit_unix_listener(path, fd)
      @unix_paths << path

      s = UNIXServer.for_fd fd
      @ios << s

      s
    end

    def backlog
      @thread_pool and @thread_pool.backlog
    end

    def running
      @thread_pool and @thread_pool.spawned
    end

    # Runs the server.  It returns the thread used so you can join it.
    # The thread is always available via #thread to be join'd
    #
    def run
      BasicSocket.do_not_reverse_lookup = true

      @status = :run

      @thread_pool = ThreadPool.new(@min_threads, @max_threads) do |client, env|
        process_client(client, env)
      end

      if @auto_trim_time
        @thread_pool.auto_trim!(@auto_trim_time)
      end

      @thread = Thread.new do
        begin
          check = @check
          sockets = @ios
          pool = @thread_pool

          while @status == :run
            begin
              ios = IO.select sockets
              ios.first.each do |sock|
                if sock == check
                  break if handle_check
                else
                  pool << [sock.accept, @envs.fetch(sock, @proto_env)]
                end
              end
            rescue Errno::ECONNABORTED
              # client closed the socket even before accept
              client.close rescue nil
            rescue Object => e
              @events.unknown_error self, e, "Listen loop"
            end
          end

          graceful_shutdown if @status == :stop
        ensure
          unless @status == :restart
            @ios.each { |i| i.close }
            @unix_paths.each { |i| File.unlink i }
          end
        end
      end

      return @thread
    end

    # :nodoc:
    def handle_check
      cmd = @check.read(1) 

      case cmd
      when STOP_COMMAND
        @status = :stop
        return true
      when HALT_COMMAND
        @status = :halt
        return true
      when RESTART_COMMAND
        @status = :restart
        return true
      end

      return false
    end

    # Given a connection on +client+, handle the incoming requests.
    #
    # This method support HTTP Keep-Alive so it may, depending on if the client
    # indicates that it supports keep alive, wait for another request before
    # returning.
    #
    def process_client(client, proto_env)
      parser = HttpParser.new
      close_socket = true

      begin
        while true
          parser.reset

          env = proto_env.dup
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

              case handle_request(env, client, parser.body, cl)
              when false
                return
              when :async
                close_socket = false
                return
              end

              nparsed += parser.body.bytesize if cl

              if data.bytesize > nparsed
                data.slice!(0, nparsed)
                parser.reset
                env = @proto_env.dup
                nparsed = 0
              else
                unless ret = IO.select([client, @persistent_check], nil, nil, @persistent_timeout)
                  raise EOFError, "Timed out persistent connection"
                end

                return if ret.first.include? @persistent_check
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

      # The client disconnected while we were reading data
      rescue EOFError, SystemCallError
        # Swallow them. The ensure tries to close +client+ down

      # The client doesn't know HTTP well
      rescue HttpParserError => e
        @events.parse_error self, env, e

      # Server error
      rescue StandardError => e
        @events.unknown_error self, e, "Read"

      ensure
        begin
          client.close if close_socket
        rescue IOError, SystemCallError
          # Already closed
        rescue StandardError => e
          @events.unknown_error self, e, "Client"
        end
      end
    end

    # Given a Hash +env+ for the request read from +client+, add
    # and fixup keys to comply with Rack's env guidelines.
    #
    def normalize_env(env, client)
      if host = env[HTTP_HOST]
        if colon = host.index(":")
          env[SERVER_NAME] = host[0, colon]
          env[SERVER_PORT] = host[colon+1, host.bytesize]
        else
          env[SERVER_NAME] = host
          env[SERVER_PORT] = PORT_80
        end
      else
        env[SERVER_NAME] = LOCALHOST
        env[SERVER_PORT] = PORT_80
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

    # The object used for a request with no body. All requests with
    # no body share this one object since it has no state.
    EmptyBody = NullIO.new

    # Given the request +env+ from +client+ and a partial request body
    # in +body+, finish reading the body if there is one and invoke
    # the rack app. Then construct the response and write it back to
    # +client+
    #
    # +cl+ is the previously fetched Content-Length header if there
    # was one. This is an optimization to keep from having to look
    # it up again.
    #
    def handle_request(env, client, body, cl)
      normalize_env env, client

      if cl
        body = read_body env, client, body, cl
        return false unless body
      else
        body = EmptyBody
      end

      env[RACK_INPUT] = body
      env[RACK_URL_SCHEME] =  env[HTTPS_KEY] ? HTTPS : HTTP

      # A rack extension. If the app writes #call'ables to this
      # array, we will invoke them when the request is done.
      #
      after_reply = env[RACK_AFTER_REPLY] = []

      begin
        begin
          status, headers, res_body = @app.call(env)

          if status == -1
            unless headers.empty? and res_body == []
              raise "async response must have empty headers and body"
            end

            return :async
          end
        rescue => e
          @events.unknown_error self, e, "Rack app"

          status, headers, res_body = lowlevel_error(e)
        end

        content_length = nil
        no_body = false

        if res_body.kind_of? Array and res_body.size == 1
          content_length = res_body[0].bytesize
        end

        cork_socket client

        if env[HTTP_VERSION] == HTTP_11
          allow_chunked = true
          keep_alive = env[HTTP_CONNECTION] != CLOSE
          include_keepalive_header = false

          # An optimization. The most common response is 200, so we can
          # reply with the proper 200 status without having to compute
          # the response header.
          #
          if status == 200
            client.write HTTP_11_200
          else
            client.write "HTTP/1.1 "
            client.write status.to_s
            client.write " "
            client.write HTTP_STATUS_CODES[status]
            client.write "\r\n"

            no_body = status < 200 || STATUS_WITH_NO_ENTITY_BODY[status]
          end
        else
          allow_chunked = false
          keep_alive = env[HTTP_CONNECTION] == KEEP_ALIVE
          include_keepalive_header = keep_alive

          # Same optimization as above for HTTP/1.1
          #
          if status == 200
            client.write HTTP_10_200
          else
            client.write "HTTP/1.1 "
            client.write status.to_s
            client.write " "
            client.write HTTP_STATUS_CODES[status]
            client.write "\r\n"

            no_body = status < 200 || STATUS_WITH_NO_ENTITY_BODY[status]
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
          when CONTENT_TYPE
            next if no_body
          end

          vs.split(NEWLINE).each do |v|
            client.write k
            client.write colon
            client.write v
            client.write line_ending
          end
        end

        if no_body
          client.write line_ending
          return keep_alive
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
            client.write part.bytesize.to_s(16)
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

    # Given the requset +env+ from +client+ and the partial body +body+
    # plus a potential Content-Length value +cl+, finish reading
    # the body and return it.
    #
    # If the body is larger than MAX_BODY, a Tempfile object is used
    # for the body, otherwise a StringIO is used.
    #
    def read_body(env, client, body, cl)
      content_length = cl.to_i

      remain = content_length - body.bytesize

      return StringIO.new(body) if remain <= 0

      # Use a Tempfile if there is a lot of data left
      if remain > MAX_BODY
        stream = Tempfile.new(Const::PUMA_TMP_BASE)
        stream.binmode
        stream.write body
      else
        stream = StringIO.new body
      end

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

    # A fallback rack response if +@app+ raises as exception.
    #
    def lowlevel_error(e)
      [500, {}, ["Puma caught this error: #{e}\n#{e.backtrace.join("\n")}"]]
    end

    # Wait for all outstanding requests to finish.
    #
    def graceful_shutdown
      @thread_pool.shutdown if @thread_pool
    end

    # Stops the acceptor thread and then causes the worker threads to finish
    # off the request queue before finally exiting.
    #
    def stop(sync=false)
      @persistent_wakeup.close
      @notify << STOP_COMMAND

      @thread.join if @thread && sync
    end

    def halt(sync=false)
      @persistent_wakeup.close
      @notify << HALT_COMMAND

      @thread.join if @thread && sync
    end

    def begin_restart
      @persistent_wakeup.close
      @notify << RESTART_COMMAND
    end
  end
end
