# frozen_string_literal: true

module Puma

  #———————————————————————— DO NOT USE — this class is for internal use only ———


  # This module is included in `Client`.  It contains code to process the `env`
  # before it is passed to the app.
  #
  module ClientEnv # :nodoc:

    include Puma::Const

    # Given a Hash +env+ for the request read from +client+, add
    # and fixup keys to comply with Rack's env guidelines.
    # @param env [Hash] see Puma::Client#env, from request
    # @param client [Puma::Client] only needed for Client#peerip
    #
    def normalize_env
      if host = @env[HTTP_HOST]
        # host can be a hostname, ipv4 or bracketed ipv6. Followed by an optional port.
        if colon = host.rindex("]:") # IPV6 with port
          @env[SERVER_NAME] = host[0, colon+1]
          @env[SERVER_PORT] = host[colon+2, host.bytesize]
        elsif !host.start_with?("[") && colon = host.index(":") # not hostname or IPV4 with port
          @env[SERVER_NAME] = host[0, colon]
          @env[SERVER_PORT] = host[colon+1, host.bytesize]
        else
          @env[SERVER_NAME] = host
          @env[SERVER_PORT] = default_server_port
        end
      else
        @env[SERVER_NAME] = LOCALHOST
        @env[SERVER_PORT] = default_server_port
      end

      unless @env[REQUEST_PATH]
        # it might be a dumbass full host request header
        uri = begin
          URI.parse(@env[REQUEST_URI])
        rescue URI::InvalidURIError
          raise Puma::HttpParserError
        end
        @env[REQUEST_PATH] = uri.path

        # A nil env value will cause a LintError (and fatal errors elsewhere),
        # so only set the env value if there actually is a value.
        @env[QUERY_STRING] = uri.query if uri.query
      end

      @env[PATH_INFO] = @env[REQUEST_PATH].to_s # #to_s in case it's nil

      # From https://www.ietf.org/rfc/rfc3875 :
      # "Script authors should be aware that the REMOTE_ADDR and
      # REMOTE_HOST meta-variables (see sections 4.1.8 and 4.1.9)
      # may not identify the ultimate source of the request.
      # They identify the client for the immediate request to the
      # server; that client may be a proxy, gateway, or other
      # intermediary acting on behalf of the actual source client."
      #

      unless @env.key?(REMOTE_ADDR)
        begin
          addr = peerip
        rescue Errno::ENOTCONN
          # Client disconnects can result in an inability to get the
          # peeraddr from the socket; default to unspec.
          if peer_family == Socket::AF_INET6
            addr = UNSPECIFIED_IPV6
          else
            addr = UNSPECIFIED_IPV4
          end
        end

        # Set unix socket addrs to localhost
        if addr.empty?
          addr = peer_family == Socket::AF_INET6 ? LOCALHOST_IPV6 : LOCALHOST_IPV4
        end

        @env[REMOTE_ADDR] = addr
      end

      # The legacy HTTP_VERSION header can be sent as a client header.
      # Rack v4 may remove using HTTP_VERSION.  If so, remove this line.
      @env[HTTP_VERSION] = @env[SERVER_PROTOCOL] if @env_set_http_version

      @env[PUMA_SOCKET] = @io

      if @env[HTTPS_KEY] && @io.peercert
        @env[PUMA_PEERCERT] = @io.peercert
      end

      @env[HIJACK_P] = true
      @env[HIJACK] = method(:full_hijack).to_proc

      @env[RACK_INPUT] = @body || EmptyBody
      @env[RACK_URL_SCHEME] ||= default_server_port == PORT_443 ? HTTPS : HTTP
    end

    # Fixup any headers with `,` in the name to have `_` now. We emit
    # headers with `,` in them during the parse phase to avoid ambiguity
    # with the `-` to `_` conversion for critical headers. But here for
    # compatibility, we'll convert them back. This code is written to
    # avoid allocation in the common case (ie there are no headers
    # with `,` in their names), that's why it has the extra conditionals.
    #
    # @note If a normalized version of a `,` header already exists, we ignore
    #       the `,` version. This prevents clobbering headers managed by proxies
    #       but not by clients (Like X-Forwarded-For).
    #
    # @param env [Hash] see Puma::Client#env, from request, modifies in place
    # @version 5.0.3
    #
    def req_env_post_parse
      to_delete = nil
      to_add = nil

      @env.each do |k,v|
        if k.start_with?("HTTP_") && k.include?(",") && !UNMASKABLE_HEADERS.key?(k)
          if to_delete
            to_delete << k
          else
            to_delete = [k]
          end

          new_k = k.tr(",", "_")
          if @env.key?(new_k)
            next
          end

          unless to_add
            to_add = {}
          end

          to_add[new_k] = v
        end
      end

      if to_delete # rubocop:disable Style/SafeNavigation
        to_delete.each { |k| env.delete(k) }
      end

      if to_add
        @env.merge! to_add
      end

      # A rack extension. If the app writes #call'ables to this
      # array, we will invoke them when the request is done.
      #
      env[RACK_AFTER_REPLY] ||= []
      env[RACK_RESPONSE_FINISHED] ||= []
    end

    HTTP_ON_VALUES = { "on" => true, HTTPS => true }
    private_constant :HTTP_ON_VALUES

    # @return [Puma::Const::PORT_443,Puma::Const::PORT_80]
    #
    def default_server_port
      if HTTP_ON_VALUES[@env[HTTPS_KEY]] ||
          @env[HTTP_X_FORWARDED_PROTO]&.start_with?(HTTPS) ||
          @env[HTTP_X_FORWARDED_SCHEME] == HTTPS ||
          @env[HTTP_X_FORWARDED_SSL] == "on"
        PORT_443
      else
        PORT_80
      end
    end
  end
end
