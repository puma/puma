# frozen_string_literal: true

require 'socket'
require_relative '../test_puma'
require_relative 'puma_socket_include'
require_relative 'response'

module TestPuma

  # @!macro [new] req
  #   @param req [String, GET_11] request path

  # @!macro [new] skt
  #   @param host [String] tcp/ssl host
  #   @param port [Integer/String] tcp/ssl port
  #   @param path [String] unix socket, full path
  #   @param ctx  [OpenSSL::SSL::SSLContext] ssl context
  #   @param session: [OpenSSL::SSL::Session] ssl session

  # @!macro [new] resp
  #   @param timeout [Float, nil] total socket read timeout, defaults to `RESP_READ_TIMEOUT`
  #   @param len [ Integer, nil] the `read_nonblock` maxlen, defaults to `RESP_READ_LEN`

  # This module is included in CI test files, and provides methods to create
  # client sockets.  Normally, the socket parameters are defined by the code
  # creating the Puma server (in-process or spawned), so they do not need to be
  # specified.  Regardless, many of the less frequently used parameters still
  # have keyword arguments and they can be set to whatever is required.
  #
  # This module closes all sockets and performs all reads non-blocking and all
  # writes using syswrite.  These are helpful for reliable tests.  Please do not
  # use native Ruby sockets except if absolutely necessary.
  #
  # #### Methods that return a socket or sockets:
  # * `new_socket` - Opens a socket
  # * `send_http` - Opens a socket and sends a request, which defaults to `GET_11`
  # * `send_http_array` - Creates an array of sockets. It opens each and sends a request on each
  #
  # All methods that create a socket have the following optional keyword parameters:
  # * `host:` - tcp/ssl host (`String`)
  # * `port:` - tcp/ssl port (`Integer`, `String`)
  # * `path:` -  unix socket, full path (`String`)
  # * `ctx:` - ssl context (`OpenSSL::SSL::SSLContext`)
  # * `session:` - ssl session (`OpenSSL::SSL::Session`)
  #
  # #### Methods that process the response:
  # * `send_http_read_response` - sends a request and returns the whole response
  # * `send_http_read_body`/`send_http_read_resp_body` - sends a request and returns the response body
  # * `send_http_read_headers`/`send_http_read_resp_headers` - sends a request and returns the response with the body
  #    removed as an array of lines
  #
  # All methods that process the response have the following optional keyword parameters:
  # * `timeout:` - total socket read timeout, defaults to `RESP_READ_TIMEOUT` (`Float`)
  # * `len:` - the `read_nonblock` maxlen, defaults to `RESP_READ_LEN` (`Integer`)
  #
  # #### Methods available on socket instances:
  # * `read_response` - reads the response and returns it
  # * `read_body` - reads the response and returns the body
  # * `read_all` - reads all available data on the socket
  # * `send_http`/`<<`/`req_write` - writes to the socket with `syswrite`, returns the socket
  #
  module PumaSocket
    GET_10 = "GET / HTTP/1.0\r\n\r\n"
    GET_11 = "GET / HTTP/1.1\r\n\r\n"

    HELLO_11 = "HTTP/1.1 200 OK\r\ncontent-type: text/plain\r\n" \
      "Content-Length: 11\r\n\r\nHello World"

    RESP_READ_LEN = PumaSocketInclude::RESP_READ_LEN
    RESP_READ_TIMEOUT = PumaSocketInclude::RESP_READ_TIMEOUT
    NO_ENTITY_BODY = PumaSocketInclude::NO_ENTITY_BODY
    EMPTY_200 = [200, {}, ['']]

    HAS_APPEND_AS_BYTES = ::String.new.respond_to? :append_as_bytes

    UTF8 = ::Encoding::UTF_8

    SET_TCP_NODELAY = Socket.const_defined?(:IPPROTO_TCP) && ::Socket.const_defined?(:TCP_NODELAY)

    def before_setup
      @bind_port = nil
      @bind_path = nil
      @control_port = nil
      @control_path = nil
      @ssl_socket_contexts = Queue.new
      @ios_to_close ||= Queue.new
      super
    end

    # Closes all io's in `@ios_to_close`, also deletes them if they are files
    def after_teardown
      return if skipped?
      super
      close_ios if @ios_to_close

      return unless @ssl_socket_contexts

      @ssl_socket_contexts.pop until @ssl_socket_contexts.empty?
      @ssl_socket_contexts.close
      @ssl_socket_contexts = nil
    end

    def close_ios
      until @ios_to_close.empty?
        io = @ios_to_close.pop
        begin
          if io.respond_to? :sysclose
            io.sync_close = true
            io.sysclose unless io.closed?
          else
            io.close if io.respond_to?(:close) && !io.closed?
            if io.is_a?(File) && (path = io&.path) && File.exist?(path)
              File.unlink path
            end
          end
        rescue Errno::EBADF, Errno::ENOENT, IOError
        ensure
          io = nil
        end
      end
      @ios_to_close = nil
    end

    # rubocop: disable Metrics/ParameterLists

    # Sends a request and returns the response header lines as an array of strings.
    # Includes the status line.
    # @!macro req
    # @!macro skt
    # @!macro resp
    # @return [Array<String>] array of header lines in the response
    def send_http_read_headers(req = GET_11, host: nil, port: nil, path: nil, ctx: nil,
        session: nil, len: nil, timeout: nil)
      send_http(req, host: host, port: port, path: path, ctx: ctx, session: session)
        .read_response(timeout: timeout, len: len)
        .split(RESP_SPLIT, 2).first.split "\r\n"
    end

    # Sends a request and returns the HTTP response body.
    # @!macro req
    # @!macro skt
    # @!macro resp
    # @return [Response] the body portion of the HTTP response
    def send_http_read_body(req = GET_11, host: nil, port: nil, path: nil, ctx: nil,
        session: nil, len: nil, timeout: nil)
      send_http(req, host: host, port: port, path: path, ctx: ctx, session: session)
        .read_body(timeout: timeout, len: len)
    end

    alias :send_http_read_resp_headers :send_http_read_headers
    alias :send_http_read_resp_body    :send_http_read_body

    # Sends a request and returns whatever can be read.  Use when multiple
    # responses are sent by the server
    # @!macro req
    # @!macro skt
    # @!macro resp
    # @return [String] socket read string
    def send_http_read_all(req = GET_11, host: nil, port: nil, path: nil, ctx: nil,
        session: nil, len: RESP_READ_LEN, timeout: 15)
      send_http(req, host: host, port: port, path: path, ctx: ctx, session: session)
        .read_all(timeout: timeout, len: len)
    end

    # Sends a request and returns the HTTP response.  Assumes one response is sent.
    # @!macro req
    # @!macro skt
    # @!macro resp
    # @return [Response] the HTTP response
    def send_http_read_response(req = GET_11, host: nil, port: nil, path: nil, ctx: nil,
        session: nil, len: nil, timeout: nil)
      send_http(req, host: host, port: port, path: path, ctx: ctx, session: session)
        .read_response(timeout: timeout, len: len)
    end

    # Sends a request and returns the socket
    # @param req [String, nil] The request stirng.
    # @!macro req
    # @!macro skt
    # @return [PumaSSLSocket, PumaTCPSocket, PumaUNIXSocket] the created socket
    def send_http(req = GET_11, host: nil, port: nil, path: nil, ctx: nil, session: nil)
      new_socket(host: host, port: port, path: path, ctx: ctx, session: session)
        .send_http req
    end

    # Determines whether the socket has been closed by the server.  Only works when
    # `Socket::TCP_INFO is defined`, linux/Ubuntu
    # @param socket [PumaSSLSocket, PumaTCPSocket, PumaUNIXSocket]
    # @return [Boolean] true if closed by server, false is indeterminate, as
    #   it may not be writable
    #
    def skt_closed_by_server(socket)
      skt = socket.to_io
      return false unless skt.kind_of?(TCPSocket)

      begin
        tcp_info = skt.getsockopt(Socket::IPPROTO_TCP, Socket::TCP_INFO)
      rescue IOError, SystemCallError
        false
      else
        state = tcp_info.unpack('C')[0]
        # TIME_WAIT: 6, CLOSE: 7, CLOSE_WAIT: 8, LAST_ACK: 9, CLOSING: 11
        (state >= 6 && state <= 9) || state == 11
      end
    end

    # Helper for creating an `OpenSSL::SSL::SSLContext`.
    # @param &blk [Block] Passed the SSLContext.
    # @yield [OpenSSL::SSL::SSLContext]
    # @return [OpenSSL::SSL::SSLContext] The new socket
    def new_ctx(&blk)
      ctx = OpenSSL::SSL::SSLContext.new
      if blk
        yield ctx
      else
        ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      ctx
    end

    # Creates a new client socket.  TCP, SSL, and UNIX are supported
    # @!macro req
    # @return [PumaSSLSocket, PumaTCPSocket, PumaUNIXSocket] the created socket
    #
    def new_socket(host: nil, port: nil, path: nil, ctx: nil, session: nil)
      port  ||= @bind_port
      path  ||= @bind_path
      ip ||= (host || HOST.ip).gsub RE_HOST_TO_IP, ''  # in case a URI style IPv6 is passed

      skt =
        if path && !port && !ctx
          PumaUNIXSocket.new path.sub(/\A@/, "\0") # sub is for abstract
        elsif port # && !path
          tcp = PumaTCPSocket.new ip, port.to_i
          tcp.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1) if SET_TCP_NODELAY
          if ctx
            @ssl_socket_contexts << ctx if @ssl_socket_contexts
            PumaSSLSocket.new tcp, ctx
          else
            tcp
          end
        else
          raise 'port or path must be set!'
        end

      @ios_to_close << skt
      if ctx
        skt.session = session if session
        skt.sync_close = true
        skt.connect
      end
      skt
    end

    # Creates an array of sockets, sending a request on each
    # @param req [String] the request
    # @param len [Integer] the number of requests to send
    # @return [Array<PumaSSLSocket, PumaTCPSocket, PumaUNIXSocket>]
    #
    def send_http_array(req = GET_11, len, dly: 0.000_1, max_retries: 5)
      Array.new(len) {
        retries = 0
        begin
          skt = send_http req
          sleep dly if dly
          skt
        rescue Errno::ECONNREFUSED
          retries += 1
          if retries < max_retries
            retry
          else
            flunk 'Generate requests failed from Errno::ECONNREFUSED'
          end
        end
      }
    end

    # Reads an array of sockets that have already had requests sent.
    # @param skts [Array<Sockets]] an array of sockets that have already had
    #    requests sent
    # @return [Array<String, Class>] an array matching the order of the parameter
    #  `skts`, contains the response or the error class generated by the socket.
    #
    def read_response_array(skts, resp_count: nil, body_only: nil)
      results = Array.new skts.length
      Thread.new do
        until skts.compact.empty?
          skts.each_with_index do |skt, idx|
            next if skt.nil?
            begin
              next unless skt.wait_readable 0.000_5
              if resp_count
                resp = skt.read_response.dup
                cntr = 0
                until resp.split(RESP_SPLIT).length == resp_count + 1 || cntr > 20
                  cntr += 1
                  Thread.pass
                  if skt.wait_readable 0.001
                    begin
                      resp << skt.read_response
                    rescue EOFError
                      break
                    end
                  end
                end
                results[idx] = resp
              else
                results[idx] = body_only ? skt.read_body : skt.read_response
              end
            rescue StandardError => e
              results[idx] = e.class
            end
            begin
              skt.close unless skt.closed? # skt.close may return Errno::EBADF
            rescue StandardError => e
              results[idx] ||= e.class
            end
            skts[idx] = nil
          end
        end
      end.join 15
      results
    end
  end
end
