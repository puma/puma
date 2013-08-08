require 'rack'
require 'stringio'

require 'puma/thread_pool'
require 'puma/const'
require 'puma/events'
require 'puma/null_io'
require 'puma/compat'
require 'puma/reactor'
require 'puma/client'
require 'puma/binder'
require 'puma/delegation'
require 'puma/accept_nonblock'
require 'puma/util'

require 'puma/rack_patch'

require 'puma/puma_http11'

unless Puma.const_defined? "IOBuffer"
  require 'puma/io_buffer'
end

require 'socket'

module Puma

  # The HTTP Server itself. Serves out a single Rack app.
  class Server

    include Puma::Const
    extend  Puma::Delegation

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
    def initialize(app, events=Events.stdio, options={})
      @app = app
      @events = events

      @check, @notify = Puma::Util.pipe

      @status = :stop

      @min_threads = 0
      @max_threads = 16
      @auto_trim_time = 1

      @thread = nil
      @thread_pool = nil

      @persistent_timeout = PERSISTENT_TIMEOUT

      @binder = Binder.new(events)
      @own_binder = true

      @first_data_timeout = FIRST_DATA_TIMEOUT

      @leak_stack_on_error = true

      @options = options

      ENV['RACK_ENV'] ||= "development"

      @mode = :http
    end

    attr_accessor :binder, :leak_stack_on_error

    forward :add_tcp_listener,  :@binder
    forward :add_ssl_listener,  :@binder
    forward :add_unix_listener, :@binder

    def inherit_binder(bind)
      @binder = bind
      @own_binder = false
    end

    def tcp_mode!
      @mode = :tcp
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
        begin
          socket.setsockopt(6, 3, 0) if socket.kind_of? TCPSocket
        rescue IOError
        end
      end
    else
      def cork_socket(socket)
      end

      def uncork_socket(socket)
      end
    end

    def backlog
      @thread_pool and @thread_pool.backlog
    end

    def running
      @thread_pool and @thread_pool.spawned
    end

    # Lopez Mode == raw tcp apps

    def run_lopez_mode(background=true)
      @thread_pool = ThreadPool.new(@min_threads,
                                    @max_threads,
                                    Hash) do |client, tl|

        io = client.to_io
        addr = io.peeraddr.last

        if addr.empty?
          # Set unix socket addrs to localhost
          addr = "127.0.0.1:0"
        else
          addr = "#{addr}:#{io.peeraddr[1]}"
        end

        env = { 'thread' => tl, REMOTE_ADDR => addr }

        begin
          @app.call env, client.to_io
        rescue Object => e
          STDERR.puts "! Detected exception at toplevel: #{e.message} (#{e.class})"
          STDERR.puts e.backtrace
        end

        client.close unless env['detach']
      end

      if background
        @thread = Thread.new { handle_servers_lopez_mode }
        return @thread
      else
        handle_lopez_servers
      end
    end

    def handle_servers_lopez_mode
      begin
        check = @check
        sockets = [check] + @binder.ios
        pool = @thread_pool

        while @status == :run
          begin
            ios = IO.select sockets
            ios.first.each do |sock|
              if sock == check
                break if handle_check
              else
                begin
                  if io = sock.accept_nonblock
                    c = Client.new io, nil
                    pool << c
                  end
                rescue SystemCallError
                end
              end
            end
          rescue Errno::ECONNABORTED
            # client closed the socket even before accept
            client.close rescue nil
          rescue Object => e
            @events.unknown_error self, e, "Listen loop"
          end
        end

        graceful_shutdown if @status == :stop || @status == :restart

      rescue Exception => e
        STDERR.puts "Exception handling servers: #{e.message} (#{e.class})"
        STDERR.puts e.backtrace
      ensure
        @check.close
        @notify.close

        if @status != :restart and @own_binder
          @binder.close
        end
      end
    end
    # Runs the server.
    #
    # If +background+ is true (the default) then a thread is spun
    # up in the background to handle requests. Otherwise requests
    # are handled synchronously.
    #
    def run(background=true)
      BasicSocket.do_not_reverse_lookup = true

      @status = :run

      if @mode == :tcp
        return run_lopez_mode(background)
      end

      @thread_pool = ThreadPool.new(@min_threads,
                                    @max_threads,
                                    IOBuffer) do |client, buffer|
        process_now = false

        begin
          process_now = client.eagerly_finish
        rescue HttpParserError => e
          client.write_400
          client.close

          @events.parse_error self, client.env, e
        rescue ConnectionError
          client.close
        else
          if process_now
            process_client client, buffer
          else
            client.set_timeout @first_data_timeout
            @reactor.add client
          end
        end
      end

      @reactor = Reactor.new self, @thread_pool

      @reactor.run_in_thread

      if @auto_trim_time
        @thread_pool.auto_trim!(@auto_trim_time)
      end

      if background
        @thread = Thread.new { handle_servers }
        return @thread
      else
        handle_servers
      end
    end

    def handle_servers
      begin
        check = @check
        sockets = [check] + @binder.ios
        pool = @thread_pool

        while @status == :run
          begin
            ios = IO.select sockets
            ios.first.each do |sock|
              if sock == check
                break if handle_check
              else
                begin
                  if io = sock.accept_nonblock
                    c = Client.new io, @binder.env(sock)
                    pool << c
                  end
                rescue SystemCallError
                end
              end
            end
          rescue Errno::ECONNABORTED
            # client closed the socket even before accept
            client.close rescue nil
          rescue Object => e
            @events.unknown_error self, e, "Listen loop"
          end
        end

        graceful_shutdown if @status == :stop || @status == :restart
        @reactor.clear! if @status == :restart

        @reactor.shutdown
      rescue Exception => e
        STDERR.puts "Exception handling servers: #{e.message} (#{e.class})"
        STDERR.puts e.backtrace
      ensure
        @check.close
        @notify.close

        if @status != :restart and @own_binder
          @binder.close
        end
      end
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
    def process_client(client, buffer)
      begin
        close_socket = true

        while true
          case handle_request(client, buffer)
          when false
            return
          when :async
            close_socket = false
            return
          when true
            buffer.reset

            unless client.reset(@status == :run)
              close_socket = false
              client.set_timeout @persistent_timeout
              @reactor.add client
              return
            end
          end
        end

      # The client disconnected while we were reading data
      rescue ConnectionError
        # Swallow them. The ensure tries to close +client+ down

      # The client doesn't know HTTP well
      rescue HttpParserError => e
        client.write_400

        @events.parse_error self, client.env, e

      # Server error
      rescue StandardError => e
        client.write_500

        @events.unknown_error self, e, "Read"

      ensure
        buffer.reset

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
          env[SERVER_PORT] = default_server_port(env)
        end
      else
        env[SERVER_NAME] = LOCALHOST
        env[SERVER_PORT] = default_server_port(env)
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

      addr = client.peeraddr.last

      # Set unix socket addrs to localhost
      addr = "127.0.0.1" if addr.empty?

      env[REMOTE_ADDR] = addr
    end

    def default_server_port(env)
      env['HTTP_X_FORWARDED_PROTO'] == 'https' ? PORT_443 : PORT_80
    end

    # Given the request +env+ from +client+ and a partial request body
    # in +body+, finish reading the body if there is one and invoke
    # the rack app. Then construct the response and write it back to
    # +client+
    #
    # +cl+ is the previously fetched Content-Length header if there
    # was one. This is an optimization to keep from having to look
    # it up again.
    #
    def handle_request(req, lines)
      env = req.env
      client = req.io

      normalize_env env, client

      env[PUMA_SOCKET] = client

      env[HIJACK_P] = true
      env[HIJACK] = req

      body = req.body

      head = env[REQUEST_METHOD] == HEAD

      env[RACK_INPUT] = body
      env[RACK_URL_SCHEME] =  env[HTTPS_KEY] ? HTTPS : HTTP

      # A rack extension. If the app writes #call'ables to this
      # array, we will invoke them when the request is done.
      #
      after_reply = env[RACK_AFTER_REPLY] = []

      begin
        begin
          status, headers, res_body = @app.call(env)

          return :async if req.hijacked

          status = status.to_i

          if status == -1
            unless headers.empty? and res_body == []
              raise "async response must have empty headers and body"
            end

            return :async
          end
        rescue StandardError => e
          @events.unknown_error self, e, "Rack app"

          status, headers, res_body = lowlevel_error(e)
        end

        content_length = nil
        no_body = head

        if res_body.kind_of? Array and res_body.size == 1
          content_length = res_body[0].bytesize
        end

        cork_socket client

        line_ending = LINE_END
        colon = COLON

        if env[HTTP_VERSION] == HTTP_11
          allow_chunked = true
          keep_alive = env[HTTP_CONNECTION] != CLOSE
          include_keepalive_header = false

          # An optimization. The most common response is 200, so we can
          # reply with the proper 200 status without having to compute
          # the response header.
          #
          if status == 200
            lines << HTTP_11_200
          else
            lines.append "HTTP/1.1 ", status.to_s, " ",
                         fetch_status_code(status), line_ending

            no_body ||= status < 200 || STATUS_WITH_NO_ENTITY_BODY[status]
          end
        else
          allow_chunked = false
          keep_alive = env[HTTP_CONNECTION] == KEEP_ALIVE
          include_keepalive_header = keep_alive

          # Same optimization as above for HTTP/1.1
          #
          if status == 200
            lines << HTTP_10_200
          else
            lines.append "HTTP/1.0 ", status.to_s, " ",
                         fetch_status_code(status), line_ending

            no_body ||= status < 200 || STATUS_WITH_NO_ENTITY_BODY[status]
          end
        end

        response_hijack = nil

        headers.each do |k, vs|
          case k
          when CONTENT_LENGTH2
            content_length = vs
            next
          when TRANSFER_ENCODING
            allow_chunked = false
            content_length = nil
          when HIJACK
            response_hijack = vs
            next
          end

          if vs.respond_to?(:to_s)
            vs.to_s.split(NEWLINE).each do |v|
              lines.append k, colon, v, line_ending
            end
          else
            lines.append k, colon, line_ending
          end
        end

        if no_body
          if content_length and status != 204
            lines.append CONTENT_LENGTH_S, content_length.to_s, line_ending
          end

          lines << line_ending
          fast_write client, lines.to_s
          return keep_alive
        end

        if include_keepalive_header
          lines << CONNECTION_KEEP_ALIVE
        elsif !keep_alive
          lines << CONNECTION_CLOSE
        end

        unless response_hijack
          if content_length
            lines.append CONTENT_LENGTH_S, content_length.to_s, line_ending
            chunked = false
          elsif allow_chunked
            lines << TRANSFER_ENCODING_CHUNKED
            chunked = true
          end
        end

        lines << line_ending

        fast_write client, lines.to_s

        if response_hijack
          response_hijack.call client
          return :async
        end

        begin
          res_body.each do |part|
            if chunked
              client.syswrite part.bytesize.to_s(16)
              client.syswrite line_ending
              fast_write client, part
              client.syswrite line_ending
            else
              fast_write client, part
            end

            client.flush
          end

          if chunked
            client.syswrite CLOSE_CHUNKED
            client.flush
          end
        rescue SystemCallError, IOError
          raise ConnectionError, "Connection error detected during write"
        end

      ensure
        uncork_socket client

        body.close
        res_body.close if res_body.respond_to? :close

        after_reply.each { |o| o.call }
      end

      return keep_alive
    end

    def fetch_status_code(status)
      HTTP_STATUS_CODES.fetch(status) { 'CUSTOM' }
    end
    private :fetch_status_code

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
      else
        # The body[0,0] trick is to get an empty string in the same
        # encoding as body.
        stream = StringIO.new body[0,0]
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

    # A fallback rack response if +@app+ raises as exception.
    #
    def lowlevel_error(e)
      if @leak_stack_on_error
        [500, {}, ["Puma caught this error: #{e.message} (#{e.class})\n#{e.backtrace.join("\n")}"]]
      else
        [500, {}, ["A really lowlevel plumbing error occured. Please contact your local Maytag(tm) repair man.\n"]]
      end
    end

    # Wait for all outstanding requests to finish.
    #
    def graceful_shutdown
      if @options[:drain_on_shutdown]
        count = 0

        while true
          ios = IO.select @binder.ios, nil, nil, 0
          break unless ios

          ios.first.each do |sock|
            begin
              if io = sock.accept_nonblock
                count += 1
                c = Client.new io, @binder.env(sock)
                @thread_pool << c
              end
            rescue SystemCallError
            end
          end
        end

        @events.debug "Drained #{count} additional connections."
      end

      @thread_pool.shutdown if @thread_pool
    end

    # Stops the acceptor thread and then causes the worker threads to finish
    # off the request queue before finally exiting.
    #
    def stop(sync=false)
      begin
        @notify << STOP_COMMAND
      rescue IOError
        # The server, in another thread, is shutting down
      end

      @thread.join if @thread && sync
    end

    def halt(sync=false)
      begin
        @notify << HALT_COMMAND
      rescue IOError
        # The server, in another thread, is shutting down
      end

      @thread.join if @thread && sync
    end

    def begin_restart
      begin
        @notify << RESTART_COMMAND
      rescue IOError
        # The server, in another thread, is shutting down
      end
    end

    def fast_write(io, str)
      n = 0
      while true
        begin
          n = io.syswrite str
        rescue Errno::EAGAIN, Errno::EWOULDBLOCK
          IO.select(nil, [io], nil, 1)
          retry
        end

        return if n == str.bytesize
        str = str.byteslice(n..-1)
      end
    end
    private :fast_write
  end
end
