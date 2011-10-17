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

    def add_tcp_listener(host, port)
      @ios << TCPServer.new(host, port)
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
      begin
        while true
          parser = HttpParser.new
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
              return unless handle_request env, client, parser.body

              unless IO.select([client], nil, nil, @persistent_timeout)
                raise EOFError, "Timed out persistent connection"
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

    def handle_request(env, client, body)
      normalize_env env, client

      body = read_body env, client, body

      return false unless body

      env["rack.input"] = body
      env["rack.url_scheme"] =  env["HTTPS"] ? "https" : "http"

      if env['HTTP_VERSION'] == 'HTTP/1.1'
        http_version = "HTTP/1.1 "
        keep_alive = env["HTTP_CONNECTION"] != "close"
      else
        http_version = "HTTP/1.0 "
        keep_alive = env["HTTP_CONNECTION"] == "Keep-Alive"
      end

      chunked = false

      begin
        begin
          status, headers, res_body = @app.call(env)
        rescue => e
          status, headers, res_body = lowlevel_error(e)
        end

        content_length = nil

        if res_body.kind_of? String
          content_length = res_body.size
        elsif res_body.kind_of? Array and res_body.size == 1
          content_length = res_body[0].size
        end

        client.write http_version
        client.write status.to_s
        client.write " "
        client.write HTTP_STATUS_CODES[status]
        client.write "\r\n"

        colon = ": "
        line_ending = "\r\n"

        headers.each do |k, vs|
          if k == "Content-Length"
            content_length = vs
            next
          end

          vs.split("\n").each do |v|
            client.write k
            client.write colon
            client.write v
            client.write line_ending
          end
        end

        client.write "Connection: close\r\n" unless keep_alive

        if content_length
          client.write "Content-Length: #{content_length}\r\n"
        else
          client.write "Transfer-Encoding: chunked\r\n"
          chunked = true
        end

        client.write line_ending

        if res_body.kind_of? String
          if chunked
            client.write res_body.size.to_s(16)
            client.write line_ending
            client.write res_body
            client.write line_ending
          else
            client.write res_body
          end

          client.flush
        else
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
        end

        if chunked
          client.write "0"
          client.write line_ending
          client.flush
        end

      ensure
        body.close
        res_body.close if res_body.respond_to? :close
      end

      return keep_alive
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
      rescue LoadeError
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
