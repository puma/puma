# frozen_string_literal: true

require 'uri'
require 'socket'

require 'puma/const'
require 'puma/util'
require 'puma/configuration'

module Puma

  if HAS_SSL
    require 'puma/minissl'
    require 'puma/minissl/context_builder'

    # Odd bug in 'pure Ruby' nio4r version 2.5.2, which installs with Ruby 2.3.
    # NIO doesn't create any OpenSSL objects, but it rescues an OpenSSL error.
    # The bug was that it did not require openssl.
    # @todo remove when Ruby 2.3 support is dropped
    #
    if windows? && RbConfig::CONFIG['ruby_version'] == '2.3.0'
      require 'openssl'
    end
  end

  class Binder
    include Puma::Const

    RACK_VERSION = [1,6].freeze

    def initialize(events, conf = Configuration.new)
      @events = events
      @listeners = []
      @inherited_fds = {}
      @activated_sockets = {}
      @unix_paths = []

      @proto_env = {
        "rack.version".freeze => RACK_VERSION,
        "rack.errors".freeze => events.stderr,
        "rack.multithread".freeze => conf.options[:max_threads] > 1,
        "rack.multiprocess".freeze => conf.options[:workers] >= 1,
        "rack.run_once".freeze => false,
        RACK_URL_SCHEME => conf.options[:rack_url_scheme],
        "SCRIPT_NAME".freeze => ENV['SCRIPT_NAME'] || "",

        # I'd like to set a default CONTENT_TYPE here but some things
        # depend on their not being a default set and inferring
        # it from the content. And so if i set it here, it won't
        # infer properly.

        "QUERY_STRING".freeze => "",
        SERVER_PROTOCOL => HTTP_11,
        SERVER_SOFTWARE => PUMA_SERVER_STRING,
        GATEWAY_INTERFACE => CGI_VER
      }

      @envs = {}
      @ios = []
    end

    attr_reader :ios

    # @version 5.0.0
    attr_reader :activated_sockets, :envs, :inherited_fds, :listeners, :proto_env, :unix_paths

    # @version 5.0.0
    attr_writer :ios, :listeners

    def env(sock)
      @envs.fetch(sock, @proto_env)
    end

    def close
      @ios.each { |i| i.close }
    end

    # @!attribute [r] connected_ports
    # @version 5.0.0
    def connected_ports
      ios.map { |io| io.addr[1] }.uniq
    end

    # @version 5.0.0
    def create_inherited_fds(env_hash)
      env_hash.select {|k,v| k =~ /PUMA_INHERIT_\d+/}.each do |_k, v|
        fd, url = v.split(":", 2)
        @inherited_fds[url] = fd.to_i
      end.keys # pass keys back for removal
    end

    # systemd socket activation.
    # LISTEN_FDS = number of listening sockets. e.g. 2 means accept on 2 sockets w/descriptors 3 and 4.
    # LISTEN_PID = PID of the service process, aka us
    # @see https://www.freedesktop.org/software/systemd/man/systemd-socket-activate.html
    # @version 5.0.0
    #
    def create_activated_fds(env_hash)
      @events.debug "ENV['LISTEN_FDS'] #{ENV['LISTEN_FDS'].inspect}  env_hash['LISTEN_PID'] #{env_hash['LISTEN_PID'].inspect}"
      return [] unless env_hash['LISTEN_FDS'] && env_hash['LISTEN_PID'].to_i == $$
      env_hash['LISTEN_FDS'].to_i.times do |index|
        sock = TCPServer.for_fd(socket_activation_fd(index))
        key = begin # Try to parse as a path
          [:unix, Socket.unpack_sockaddr_un(sock.getsockname)]
        rescue ArgumentError # Try to parse as a port/ip
          port, addr = Socket.unpack_sockaddr_in(sock.getsockname)
          addr = "[#{addr}]" if addr =~ /\:/
          [:tcp, addr, port]
        end
        @activated_sockets[key] = sock
        @events.debug "Registered #{key.join ':'} for activation from LISTEN_FDS"
      end
      ["LISTEN_FDS", "LISTEN_PID"] # Signal to remove these keys from ENV
    end

    # Synthesize binds from systemd socket activation
    #
    # When systemd socket activation is enabled, it can be tedious to keep the
    # binds in sync. This method can synthesize any binds based on the received
    # activated sockets. Any existing matching binds will be respected.
    #
    # When only_matching is true in, all binds that do not match an activated
    # socket is removed in place.
    #
    # It's a noop if no activated sockets were received.
    def synthesize_binds_from_activated_fs(binds, only_matching)
      return binds unless activated_sockets.any?

      activated_binds = []

      activated_sockets.keys.each do |proto, addr, port|
        if port
          tcp_url = "#{proto}://#{addr}:#{port}"
          ssl_url = "ssl://#{addr}:#{port}"
          ssl_url_prefix = "#{ssl_url}?"

          existing = binds.find { |bind| bind == tcp_url || bind == ssl_url || bind.start_with?(ssl_url_prefix) }

          activated_binds << (existing || tcp_url)
        else
          # TODO: can there be a SSL bind without a port?
          activated_binds << "#{proto}://#{addr}"
        end
      end

      if only_matching
        activated_binds
      else
        binds | activated_binds
      end
    end

    def parse(binds, logger, log_msg = 'Listening')
      binds.each do |str|
        uri = URI.parse str
        case uri.scheme
        when "tcp"
          if fd = @inherited_fds.delete(str)
            io = inherit_tcp_listener uri.host, uri.port, fd
            logger.log "* Inherited #{str}"
          elsif sock = @activated_sockets.delete([ :tcp, uri.host, uri.port ])
            io = inherit_tcp_listener uri.host, uri.port, sock
            logger.log "* Activated #{str}"
          else
            ios_len = @ios.length
            params = Util.parse_query uri.query

            opt = params.key?('low_latency') && params['low_latency'] != 'false'
            bak = params.fetch('backlog', 1024).to_i

            io = add_tcp_listener uri.host, uri.port, opt, bak

            @ios[ios_len..-1].each do |i|
              addr = loc_addr_str i
              logger.log "* #{log_msg} on http://#{addr}"
            end
          end

          @listeners << [str, io] if io
        when "unix"
          path = "#{uri.host}#{uri.path}".gsub("%20", " ")
          abstract = false
          if str.start_with? 'unix://@'
            raise "OS does not support abstract UNIXSockets" unless Puma.abstract_unix_socket?
            abstract = true
            path = "@#{path}"
          end

          if fd = @inherited_fds.delete(str)
            @unix_paths << path unless abstract
            io = inherit_unix_listener path, fd
            logger.log "* Inherited #{str}"
          elsif sock = @activated_sockets.delete([ :unix, path ]) ||
              @activated_sockets.delete([ :unix, File.realdirpath(path) ])
            @unix_paths << path unless abstract || File.exist?(path)
            io = inherit_unix_listener path, sock
            logger.log "* Activated #{str}"
          else
            umask = nil
            mode = nil
            backlog = 1024

            if uri.query
              params = Util.parse_query uri.query
              if u = params['umask']
                # Use Integer() to respect the 0 prefix as octal
                umask = Integer(u)
              end

              if u = params['mode']
                mode = Integer('0'+u)
              end

              if u = params['backlog']
                backlog = Integer(u)
              end
            end

            @unix_paths << path unless abstract || File.exist?(path)
            io = add_unix_listener path, umask, mode, backlog
            logger.log "* #{log_msg} on #{str}"
          end

          @listeners << [str, io]
        when "ssl"

          raise "Puma compiled without SSL support" unless HAS_SSL

          params = Util.parse_query uri.query
          ctx = MiniSSL::ContextBuilder.new(params, @events).context

          if fd = @inherited_fds.delete(str)
            logger.log "* Inherited #{str}"
            io = inherit_ssl_listener fd, ctx
          elsif sock = @activated_sockets.delete([ :tcp, uri.host, uri.port ])
            io = inherit_ssl_listener sock, ctx
            logger.log "* Activated #{str}"
          else
            ios_len = @ios.length
            io = add_ssl_listener uri.host, uri.port, ctx

            @ios[ios_len..-1].each do |i|
              addr = loc_addr_str i
              logger.log "* #{log_msg} on ssl://#{addr}?#{uri.query}"
            end
          end

          @listeners << [str, io] if io
        else
          logger.error "Invalid URI: #{str}"
        end
      end

      # If we inherited fds but didn't use them (because of a
      # configuration change), then be sure to close them.
      @inherited_fds.each do |str, fd|
        logger.log "* Closing unused inherited connection: #{str}"

        begin
          IO.for_fd(fd).close
        rescue SystemCallError
        end

        # We have to unlink a unix socket path that's not being used
        uri = URI.parse str
        if uri.scheme == "unix"
          path = "#{uri.host}#{uri.path}"
          File.unlink path
        end
      end

      # Also close any unused activated sockets
      unless @activated_sockets.empty?
        fds = @ios.map(&:to_i)
        @activated_sockets.each do |key, sock|
          next if fds.include? sock.to_i
          logger.log "* Closing unused activated socket: #{key.first}://#{key[1..-1].join ':'}"
          begin
            sock.close
          rescue SystemCallError
          end
          # We have to unlink a unix socket path that's not being used
          File.unlink key[1] if key.first == :unix
        end
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
      if host == "localhost"
        loopback_addresses.each do |addr|
          add_tcp_listener addr, port, optimize_for_latency, backlog
        end
        return
      end

      host = host[1..-2] if host and host[0..0] == '['
      tcp_server = TCPServer.new(host, port)
      if optimize_for_latency
        tcp_server.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
      end
      tcp_server.setsockopt(Socket::SOL_SOCKET,Socket::SO_REUSEADDR, true)
      tcp_server.listen backlog

      @ios << tcp_server
      tcp_server
    end

    def inherit_tcp_listener(host, port, fd)
      s = fd.kind_of?(::TCPServer) ? fd : ::TCPServer.for_fd(fd)

      @ios << s
      s
    end

    def add_ssl_listener(host, port, ctx,
                         optimize_for_latency=true, backlog=1024)

      raise "Puma compiled without SSL support" unless HAS_SSL

      if host == "localhost"
        loopback_addresses.each do |addr|
          add_ssl_listener addr, port, ctx, optimize_for_latency, backlog
        end
        return
      end

      host = host[1..-2] if host[0..0] == '['
      s = TCPServer.new(host, port)
      if optimize_for_latency
        s.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
      end
      s.setsockopt(Socket::SOL_SOCKET,Socket::SO_REUSEADDR, true)
      s.listen backlog

      ssl = MiniSSL::Server.new s, ctx
      env = @proto_env.dup
      env[HTTPS_KEY] = HTTPS
      @envs[ssl] = env

      @ios << ssl
      s
    end

    def inherit_ssl_listener(fd, ctx)
      raise "Puma compiled without SSL support" unless HAS_SSL

      s = fd.kind_of?(::TCPServer) ? fd : ::TCPServer.for_fd(fd)

      ssl = MiniSSL::Server.new(s, ctx)

      env = @proto_env.dup
      env[HTTPS_KEY] = HTTPS
      @envs[ssl] = env

      @ios << ssl

      s
    end

    # Tell the server to listen on +path+ as a UNIX domain socket.
    #
    def add_unix_listener(path, umask=nil, mode=nil, backlog=1024)
      # Let anyone connect by default
      umask ||= 0

      begin
        old_mask = File.umask(umask)

        if File.exist? path
          begin
            old = UNIXSocket.new path
          rescue SystemCallError, IOError
            File.unlink path
          else
            old.close
            raise "There is already a server bound to: #{path}"
          end
        end
        s = UNIXServer.new path.sub(/\A@/, "\0") # check for abstract UNIXSocket
        s.listen backlog
        @ios << s
      ensure
        File.umask old_mask
      end

      if mode
        File.chmod mode, path
      end

      env = @proto_env.dup
      env[REMOTE_ADDR] = "127.0.0.1"
      @envs[s] = env

      s
    end

    def inherit_unix_listener(path, fd)
      s = fd.kind_of?(::TCPServer) ? fd : ::UNIXServer.for_fd(fd)

      @ios << s

      env = @proto_env.dup
      env[REMOTE_ADDR] = "127.0.0.1"
      @envs[s] = env

      s
    end

    def close_listeners
      @listeners.each do |l, io|
        io.close unless io.closed?
        uri = URI.parse l
        next unless uri.scheme == 'unix'
        unix_path = "#{uri.host}#{uri.path}"
        File.unlink unix_path if @unix_paths.include?(unix_path) && File.exist?(unix_path)
      end
    end

    def redirects_for_restart
      redirects = @listeners.map { |a| [a[1].to_i, a[1].to_i] }.to_h
      redirects[:close_others] = true
      redirects
    end

    # @version 5.0.0
    def redirects_for_restart_env
      @listeners.each_with_object({}).with_index do |(listen, memo), i|
        memo["PUMA_INHERIT_#{i}"] = "#{listen[1].to_i}:#{listen[0]}"
      end
    end

    private

    # @!attribute [r] loopback_addresses
    def loopback_addresses
      Socket.ip_address_list.select do |addrinfo|
        addrinfo.ipv6_loopback? || addrinfo.ipv4_loopback?
      end.map { |addrinfo| addrinfo.ip_address }.uniq
    end

    def loc_addr_str(io)
      loc_addr = io.to_io.local_address
      if loc_addr.ipv6?
        "[#{loc_addr.ip_unpack[0]}]:#{loc_addr.ip_unpack[1]}"
      else
        loc_addr.ip_unpack.join(':')
      end
    end

    # @version 5.0.0
    def socket_activation_fd(int)
      int + 3 # 3 is the magic number you add to follow the SA protocol
    end
  end
end
