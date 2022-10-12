# frozen_string_literal: true

module Puma
  #———————————————————————— DO NOT USE — this class is for internal use only ———


  # The methods here are included in Server, but are separated into this file.
  # All the methods here pertain to passing the request to the app, then
  # writing the response back to the client.
  #
  # None of the methods here are called externally, with the exception of
  # #handle_request, which is called in Server#process_client.
  # @version 5.0.3
  #
  module Request # :nodoc:

    # determines whether to write body to io_buffer first, or straight to socket
    # also fixes max size of chunked body read when bosy is an IO.
    BODY_LEN_MAX   = 1_024 * 256

    # size divide for using copy_stream on body
    IO_BODY_MAX = 1_024 * 64

    # max size for io_buffer, force write when exceeded
    IO_BUFFER_LEN_MAX = 1_024 * 1_024 * 4

    SOCKET_WRITE_ERR_MSG = "Socket timeout writing data"

    CUSTOM_STAT = 'CUSTOM'

    include Puma::Const

    # Takes the request contained in +client+, invokes the Rack application to construct
    # the response and writes it back to +client.io+.
    #
    # It'll return +false+ when the connection is closed, this doesn't mean
    # that the response wasn't successful.
    #
    # It'll return +:async+ if the connection remains open but will be handled
    # elsewhere, i.e. the connection has been hijacked by the Rack application.
    #
    # Finally, it'll return +true+ on keep-alive connections.
    # @param client [Puma::Client]
    # @param io_buffer [Puma::IOBuffer]
    # @param requests [Integer]
    # @return [Boolean,:async]
    #
    def handle_request(client, io_buffer, requests)
      env = client.env
      socket  = client.io   # io may be a MiniSSL::Socket

      return false if closed_socket?(socket)

      normalize_env env, client

      env[PUMA_SOCKET] = socket

      if env[HTTPS_KEY] && socket.peercert
        env[PUMA_PEERCERT] = socket.peercert
      end

      env[HIJACK_P] = true
      env[HIJACK] = client

      env[RACK_INPUT] = client.body
      env[RACK_URL_SCHEME] ||= default_server_port(env) == PORT_443 ? HTTPS : HTTP

      if @early_hints
        env[EARLY_HINTS] = lambda { |headers|
          begin
            fast_write_str socket, str_early_hints(headers)
          rescue ConnectionError => e
            @log_writer.debug_error e
            # noop, if we lost the socket we just won't send the early hints
          end
        }
      end

      req_env_post_parse env

      # A rack extension. If the app writes #call'ables to this
      # array, we will invoke them when the request is done.
      #
      env[RACK_AFTER_REPLY] ||= []

      begin
        if SUPPORTED_HTTP_METHODS.include?(env[REQUEST_METHOD])
          status, headers, res_body = @thread_pool.with_force_shutdown do
            @app.call(env)
          end
        else
          @log_writer.log "Unsupported HTTP method used: #{env[REQUEST_METHOD]}"
          status, headers, res_body = [501, {}, ["#{env[REQUEST_METHOD]} method is not supported"]]
        end

        return :async if client.hijacked

        status = status.to_i

        if status == -1
          unless headers.empty? and res_body == []
            raise "async response must have empty headers and body"
          end

          return :async
        end
      rescue ThreadPool::ForceShutdown => e
        @log_writer.unknown_error e, client, "Rack app"
        @log_writer.log "Detected force shutdown of a thread"

        status, headers, res_body = lowlevel_error(e, env, 503)
      rescue Exception => e
        @log_writer.unknown_error e, client, "Rack app"

        status, headers, res_body = lowlevel_error(e, env, 500)
      end
      prepare_response(status, headers, res_body, io_buffer, requests, client)
    end

    # Assembles the headers and prepares the body for actually sending the
    # response via #fast_write_response.
    #
    # @param status [Integer] the status returned by the Rack application
    # @param headers [Hash] the headers returned by the Rack application
    # @param app_body [Array] the body returned by the Rack application or
    #   a call to `lowlevel_error`
    # @param io_buffer [Puma::IOBuffer] modified in place
    # @param requests [Integer] number of inline requests handled
    # @param client [Puma::Client]
    # @return [Boolean,:async]
    def prepare_response(status, headers, app_body, io_buffer, requests, client)
      env = client.env
      socket  = client.io

      after_reply = env[RACK_AFTER_REPLY] || []

      return false if closed_socket?(socket)

      resp_info = str_headers(env, status, headers, app_body, io_buffer, requests, client)

      # below converts app_body into body, dependent on app_body's characteristics, and
      # resp_info[:content_length] will be set if it can be determined
      if !resp_info[:content_length] && !resp_info[:transfer_encoding] && status != 204
        if app_body.respond_to?(:to_ary)
          length = 0
          if array_body = app_body.to_ary
            body = array_body.map { |part| length += part.bytesize; part }
          elsif app_body.is_a?(::File) && app_body.respond_to?(:size)
            length = app_body.size
          elsif app_body.respond_to?(:each)
            body = []
            app_body.each { |part| length += part.bytesize; body << part }
          end
          resp_info[:content_length] = length
        elsif app_body.is_a?(File) && app_body.respond_to?(:size)
          resp_info[:content_length] = app_body.size
          body = app_body
        elsif app_body.respond_to?(:to_path) && app_body.respond_to?(:each) &&
            File.readable?(fn = app_body.to_path)
          body = File.open fn, 'rb'
          resp_info[:content_length] = body.size
        else
          body = app_body
        end
      elsif !app_body.is_a?(::File) && app_body.respond_to?(:to_path) && app_body.respond_to?(:each) &&
          File.readable?(fn = app_body.to_path)
        body = File.open fn, 'rb'
        resp_info[:content_length] = body.size
      else
        body = app_body
      end

      line_ending = LINE_END

      content_length = resp_info[:content_length]
      keep_alive     = resp_info[:keep_alive]

      if app_body && !app_body.respond_to?(:each)
        response_hijack = app_body
      else
        response_hijack = resp_info[:response_hijack]
      end

      cork_socket socket

      if resp_info[:no_body]
        if content_length and status != 204
          io_buffer.append CONTENT_LENGTH_S, content_length.to_s, line_ending
        end

        io_buffer << LINE_END
        fast_write_str socket, io_buffer.to_s
        return keep_alive
      end
      if content_length
        io_buffer.append CONTENT_LENGTH_S, content_length.to_s, line_ending
        chunked = false
      elsif !response_hijack and resp_info[:allow_chunked]
        io_buffer << TRANSFER_ENCODING_CHUNKED
        chunked = true
      end

      io_buffer << line_ending

      if response_hijack
        fast_write_str socket, io_buffer.to_s
        response_hijack.call socket
        return :async
      end

      fast_write_response socket, body, io_buffer, chunked, content_length.to_i
      keep_alive
    ensure
      io_buffer.reset
      resp_info = nil
      uncork_socket socket
      app_body.close if app_body.respond_to? :close
      client.tempfile&.unlink

      begin
        after_reply.each { |o| o.call }
      rescue StandardError => e
        @log_writer.debug_error e
      end unless after_reply.empty?
    end

    # @param env [Hash] see Puma::Client#env, from request
    # @return [Puma::Const::PORT_443,Puma::Const::PORT_80]
    #
    def default_server_port(env)
      if ['on', HTTPS].include?(env[HTTPS_KEY]) || env[HTTP_X_FORWARDED_PROTO].to_s[0...5] == HTTPS || env[HTTP_X_FORWARDED_SCHEME] == HTTPS || env[HTTP_X_FORWARDED_SSL] == "on"
        PORT_443
      else
        PORT_80
      end
    end

    # Used to write 'early hints', 'no body' responses, 'hijacked' responses,
    # and body segments (called by `fast_write_response`).
    # Writes a string to an io (normally `Client#io`) using `write_nonblock`.
    # Large strings may not be written in one pass, especially if `io` is a
    # `MiniSSL::Socket`.
    # @param io [#write_nonblock] the io to write to
    # @param str [String] the string written to the io
    # @raise [ConnectionError]
    #
    def fast_write_str(socket, str)
      n = 0
      byte_size = str.bytesize
      while n < byte_size
        begin
          n += socket.syswrite(n.zero? ? str : str.byteslice(n..-1))
        rescue Errno::EAGAIN, Errno::EWOULDBLOCK
          unless socket.wait_writable WRITE_TIMEOUT
            raise ConnectionError, SOCKET_WRITE_ERR_MSG
          end
          retry
        rescue  Errno::EPIPE, SystemCallError, IOError
          raise ConnectionError, SOCKET_WRITE_ERR_MSG
        end
      end
    end

    # Used to write headers and body.
    # Writes to a socket (normally `Client#io`) using `#fast_write_str`.
    # Accumulates `body` items into `io_buffer`, then writes to socket.
    # @param socket [#write] the response socket
    # @param body [Enumerable, File] the body object
    # @param io_buffer [Puma::IOBuffer] contains headers
    # @param chunk [Boolean]
    # @raise [ConnectionError]
    #
    def fast_write_response(socket, body, io_buffer, chunked, content_length)
      if body.is_a?(::File) || body.respond_to?(:read) || body.respond_to?(:readpartial)
        if chunked  # would this ever happen?
          while part = body.read(BODY_LEN_MAX)
            io_buffer.append part.bytesize.to_s(16), LINE_END, part, LINE_END
          end
          io_buffer << CLOSE_CHUNKED
          fast_write_str socket, io_buffer.to_s
        else
          if content_length <= IO_BODY_MAX
            io_buffer.write body.sysread(content_length)
            fast_write_str socket, io_buffer.to_s
          else
            fast_write_str socket, io_buffer.to_s
            IO.copy_stream body, socket
          end
        end
        body.close
      elsif body.is_a?(::Array) && body.length == 1
        body_first = body.first
        if body_first.is_a?(::String) && body_first.bytesize >= BODY_LEN_MAX
          # large body, write both header & body to socket
          fast_write_str socket, io_buffer.to_s
          fast_write_str socket, body_first
        else
          # smaller body, write to stream first
          io_buffer.write body_first
          fast_write_str socket, io_buffer.to_s
        end
      else
        # for array bodies, flush io_buffer to socket when size is greater than
        # IO_BUFFER_LEN_MAX
        if chunked
          body.each do |part|
            next if (byte_size = part.bytesize).zero?
            io_buffer.append byte_size.to_s(16), LINE_END, part, LINE_END
            if io_buffer.length > IO_BUFFER_LEN_MAX
              fast_write_str socket, io_buffer.to_s
              io_buffer.reset
            end
          end
          io_buffer.write CLOSE_CHUNKED
        else
          body.each do |part|
            next if part.bytesize.zero?
            io_buffer.write part
            if io_buffer.length > IO_BUFFER_LEN_MAX
              fast_write_str socket, io_buffer.to_s
              io_buffer.reset
            end
          end
        end
        fast_write_str(socket, io_buffer.to_s) unless io_buffer.length.zero?
      end
    rescue Errno::EAGAIN, Errno::EWOULDBLOCK
      raise ConnectionError, SOCKET_WRITE_ERR_MSG
    rescue  Errno::EPIPE, SystemCallError, IOError
      raise ConnectionError, SOCKET_WRITE_ERR_MSG
    end

    private :fast_write_str, :fast_write_response

    # Given a Hash +env+ for the request read from +client+, add
    # and fixup keys to comply with Rack's env guidelines.
    # @param env [Hash] see Puma::Client#env, from request
    # @param client [Puma::Client] only needed for Client#peerip
    #
    def normalize_env(env, client)
      if host = env[HTTP_HOST]
        # host can be a hostname, ipv4 or bracketed ipv6. Followed by an optional port.
        if colon = host.rindex("]:") # IPV6 with port
          env[SERVER_NAME] = host[0, colon+1]
          env[SERVER_PORT] = host[colon+2, host.bytesize]
        elsif !host.start_with?("[") && colon = host.index(":") # not hostname or IPV4 with port
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

        # A nil env value will cause a LintError (and fatal errors elsewhere),
        # so only set the env value if there actually is a value.
        env[QUERY_STRING] = uri.query if uri.query
      end

      env[PATH_INFO] = env[REQUEST_PATH].to_s # #to_s in case it's nil

      # From https://www.ietf.org/rfc/rfc3875 :
      # "Script authors should be aware that the REMOTE_ADDR and
      # REMOTE_HOST meta-variables (see sections 4.1.8 and 4.1.9)
      # may not identify the ultimate source of the request.
      # They identify the client for the immediate request to the
      # server; that client may be a proxy, gateway, or other
      # intermediary acting on behalf of the actual source client."
      #

      unless env.key?(REMOTE_ADDR)
        begin
          addr = client.peerip
        rescue Errno::ENOTCONN
          # Client disconnects can result in an inability to get the
          # peeraddr from the socket; default to unspec.
          if client.peer_family == Socket::AF_INET6
            addr = UNSPECIFIED_IPV6
          else
            addr = UNSPECIFIED_IPV4
          end
        end

        # Set unix socket addrs to localhost
        if addr.empty?
          if client.peer_family == Socket::AF_INET6
            addr = LOCALHOST_IPV6
          else
            addr = LOCALHOST_IPV4
          end
        end

        env[REMOTE_ADDR] = addr
      end

      # The legacy HTTP_VERSION header can be sent as a client header.
      # Rack v4 may remove using HTTP_VERSION.  If so, remove this line.
      env[HTTP_VERSION] = env[SERVER_PROTOCOL]
    end
    private :normalize_env

    # @param header_key [#to_s]
    # @return [Boolean]
    #
    def illegal_header_key?(header_key)
      !!(ILLEGAL_HEADER_KEY_REGEX =~ header_key.to_s)
    end

    # @param header_value [#to_s]
    # @return [Boolean]
    #
    def illegal_header_value?(header_value)
      !!(ILLEGAL_HEADER_VALUE_REGEX =~ header_value.to_s)
    end
    private :illegal_header_key?, :illegal_header_value?

    # Fixup any headers with `,` in the name to have `_` now. We emit
    # headers with `,` in them during the parse phase to avoid ambiguity
    # with the `-` to `_` conversion for critical headers. But here for
    # compatibility, we'll convert them back. This code is written to
    # avoid allocation in the common case (ie there are no headers
    # with `,` in their names), that's why it has the extra conditionals.
    # @param env [Hash] see Puma::Client#env, from request, modifies in place
    # @version 5.0.3
    #
    def req_env_post_parse(env)
      to_delete = nil
      to_add = nil

      env.each do |k,v|
        if k.start_with?("HTTP_") and k.include?(",") and k != "HTTP_TRANSFER,ENCODING"
          if to_delete
            to_delete << k
          else
            to_delete = [k]
          end

          unless to_add
            to_add = {}
          end

          to_add[k.tr(",", "_")] = v
        end
      end

      if to_delete
        to_delete.each { |k| env.delete(k) }
        env.merge! to_add
      end
    end
    private :req_env_post_parse

    # Used in the lambda for env[ `Puma::Const::EARLY_HINTS` ]
    # @param headers [Hash] the headers returned by the Rack application
    # @return [String]
    # @version 5.0.3
    #
    def str_early_hints(headers)
      eh_str = +"HTTP/1.1 103 Early Hints\r\n"
      headers.each_pair do |k, vs|
        next if illegal_header_key?(k)

        if vs.respond_to?(:to_s) && !vs.to_s.empty?
          vs.to_s.split(NEWLINE).each do |v|
            next if illegal_header_value?(v)
            eh_str << "#{k}: #{v}\r\n"
          end
        else
          eh_str << "#{k}: #{vs}\r\n"
        end
      end
      "#{eh_str}\r\n".freeze
    end
    private :str_early_hints

    # @param status [Integer] status from the app
    # @return [String] the text description from Puma::HTTP_STATUS_CODES
    #
    def fetch_status_code(status)
      HTTP_STATUS_CODES.fetch(status) { CUSTOM_STAT }
    end
    private :fetch_status_code

    # Processes and write headers to the IOBuffer.
    # @param env [Hash] see Puma::Client#env, from request
    # @param status [Integer] the status returned by the Rack application
    # @param headers [Hash] the headers returned by the Rack application
    # @param content_length [Integer,nil] content length if it can be determined from the
    #   response body
    # @param io_buffer [Puma::IOBuffer] modified inn place
    # @param requests [Integer] number of inline requests handled
    # @param client [Puma::Client]
    # @return [Hash] resp_info
    # @version 5.0.3
    #
    def str_headers(env, status, headers, res_body, io_buffer, requests, client)
      line_ending = LINE_END
      colon = COLON

      resp_info = {}
      resp_info[:no_body] = env[REQUEST_METHOD] == HEAD

      http_11 = env[SERVER_PROTOCOL] == HTTP_11
      if http_11
        resp_info[:allow_chunked] = true
        resp_info[:keep_alive] = env.fetch(HTTP_CONNECTION, "").downcase != CLOSE

        # An optimization. The most common response is 200, so we can
        # reply with the proper 200 status without having to compute
        # the response header.
        #
        if status == 200
          io_buffer << HTTP_11_200
        else
          io_buffer.append "#{HTTP_11} #{status} ", fetch_status_code(status), line_ending

          resp_info[:no_body] ||= status < 200 || STATUS_WITH_NO_ENTITY_BODY[status]
        end
      else
        resp_info[:allow_chunked] = false
        resp_info[:keep_alive] = env.fetch(HTTP_CONNECTION, "").downcase == KEEP_ALIVE

        # Same optimization as above for HTTP/1.1
        #
        if status == 200
          io_buffer << HTTP_10_200
        else
          io_buffer.append "HTTP/1.0 #{status} ",
                       fetch_status_code(status), line_ending

          resp_info[:no_body] ||= status < 200 || STATUS_WITH_NO_ENTITY_BODY[status]
        end
      end

      # regardless of what the client wants, we always close the connection
      # if running without request queueing
      resp_info[:keep_alive] &&= @queue_requests

      # Close the connection after a reasonable number of inline requests
      # if the server is at capacity and the listener has a new connection ready.
      # This allows Puma to service connections fairly when the number
      # of concurrent connections exceeds the size of the threadpool.
      resp_info[:keep_alive] &&= requests < @max_fast_inline ||
        @thread_pool.busy_threads < @max_threads ||
        !client.listener.to_io.wait_readable(0)

      resp_info[:response_hijack] = nil

      headers.each do |k, vs|
        next if illegal_header_key?(k)

        case k.downcase
        when CONTENT_LENGTH2
          next if illegal_header_value?(vs)
          resp_info[:content_length] = vs
          next
        when TRANSFER_ENCODING
          resp_info[:allow_chunked] = false
          resp_info[:content_length] = nil
          resp_info[:transfer_encoding] = vs
        when HIJACK
          resp_info[:response_hijack] = vs
          next
        when BANNED_HEADER_KEY
          next
        end

        ary = if vs.is_a?(::Array) && !vs.empty?
          vs
        elsif vs.respond_to?(:to_s) && !vs.to_s.empty?
          vs.to_s.split NEWLINE
        else
          nil
        end
        if ary
          ary.each do |v|
            next if illegal_header_value?(v)
            io_buffer.append k, colon, v, line_ending
          end
        else
          io_buffer.append k, colon, line_ending
        end
      end

      # HTTP/1.1 & 1.0 assume different defaults:
      # - HTTP 1.0 assumes the connection will be closed if not specified
      # - HTTP 1.1 assumes the connection will be kept alive if not specified.
      # Only set the header if we're doing something which is not the default
      # for this protocol version
      if http_11
        io_buffer << CONNECTION_CLOSE if !resp_info[:keep_alive]
      else
        io_buffer << CONNECTION_KEEP_ALIVE if resp_info[:keep_alive]
      end
      resp_info
    end
    private :str_headers
  end
end
