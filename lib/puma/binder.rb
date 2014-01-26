require 'puma/const'

module Puma
  class Binder
    include Puma::Const

    def initialize(events)
      @events = events
      @listeners = []
      @inherited_fds = {}
      @unix_paths = []

      @proto_env = {
        "rack.version".freeze => Rack::VERSION,
        "rack.errors".freeze => events.stderr,
        "rack.multithread".freeze => true,
        "rack.multiprocess".freeze => false,
        "rack.run_once".freeze => false,
        "SCRIPT_NAME".freeze => ENV['SCRIPT_NAME'] || "",

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
      @ios = []
    end

    attr_reader :listeners, :ios

    def env(sock)
      @envs.fetch(sock, @proto_env)
    end

    def close
      @ios.each { |i| i.close }
      @unix_paths.each { |i| File.unlink i }
    end

    def import_from_env
      remove = []

      ENV.each do |k,v|
        if k =~ /PUMA_INHERIT_\d+/
          fd, url = v.split(":", 2)
          @inherited_fds[url] = fd.to_i
          remove << k
        end
        if k =~ /LISTEN_FDS/ && ENV['LISTEN_PID'].to_i == $$
          v.to_i.times do |num|
            fd = num + 3
            sock = TCPServer.for_fd(fd)
            begin
              url = "unix://" + Socket.unpack_sockaddr_un(sock.getsockname)
            rescue ArgumentError
              port, addr = Socket.unpack_sockaddr_in(sock.getsockname)
              if addr =~ /\:/
                addr = "[#{addr}]"
              end
              url = "tcp://#{addr}:#{port}"
            end
            @inherited_fds[url] = sock
          end
          ENV.delete k
          ENV.delete 'LISTEN_PID'
        end
      end

      remove.each do |k|
        ENV.delete k
      end
    end

    def parse(binds, logger)
      binds.each do |str|
        uri = URI.parse str
        case uri.scheme
        when "tcp"
          if fd = @inherited_fds.delete(str)
            logger.log "* Inherited #{str}"
            io = inherit_tcp_listener uri.host, uri.port, fd
          else
            params = Rack::Utils.parse_query uri.query

            opt = params.key?('low_latency')
            bak = params.fetch('backlog', 1024).to_i

            logger.log "* Listening on #{str}"
            io = add_tcp_listener uri.host, uri.port, opt, bak
          end

          @listeners << [str, io]
        when "unix"
          path = "#{uri.host}#{uri.path}"

          if fd = @inherited_fds.delete(str)
            logger.log "* Inherited #{str}"
            io = inherit_unix_listener path, fd
          else
            logger.log "* Listening on #{str}"

            umask = nil

            if uri.query
              params = Rack::Utils.parse_query uri.query
              if u = params['umask']
                # Use Integer() to respect the 0 prefix as octal
                umask = Integer(u)
              end
            end

            io = add_unix_listener path, umask
          end

          @listeners << [str, io]
        when "ssl"
          if IS_JRUBY
            @events.error "SSL not supported on JRuby"
            raise UnsupportedOption
          end

          params = Rack::Utils.parse_query uri.query
          require 'puma/minissl'

          ctx = MiniSSL::Context.new
          unless params['key']
            @events.error "Please specify the SSL key via 'key='"
          end

          ctx.key = params['key']

          unless params['cert']
            @events.error "Please specify the SSL cert via 'cert='"
          end

          ctx.cert = params['cert']

          ctx.verify_mode = MiniSSL::VERIFY_NONE

          if fd = @inherited_fds.delete(str)
            logger.log "* Inherited #{str}"
            io = inherited_ssl_listener fd, ctx
          else
            logger.log "* Listening on #{str}"
            io = add_ssl_listener uri.host, uri.port, ctx
          end

          @listeners << [str, io]
        else
          logger.error "Invalid URI: #{str}"
        end
      end

      # If we inherited fds but didn't use them (because of a
      # configuration change), then be sure to close them.
      @inherited_fds.each do |str, fd|
        logger.log "* Closing unused inherited connection: #{str}"

        begin
          if fd.kind_of? TCPServer
            fd.close
          else
            IO.for_fd(fd).close
          end

        rescue SystemCallError
        end

        # We have to unlink a unix socket path that's not being used
        uri = URI.parse str
        if uri.scheme == "unix"
          path = "#{uri.host}#{uri.path}"
          File.unlink path
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
      host = host[1..-2] if host[0..0] == '['
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
      if fd.kind_of? TCPServer
        s = fd
      else
        s = TCPServer.for_fd(fd)
      end

      @ios << s
      s
    end

    def add_ssl_listener(host, port, ctx,
                         optimize_for_latency=true, backlog=1024)
      if IS_JRUBY
        @events.error "SSL not supported on JRuby"
        raise UnsupportedOption
      end

      require 'puma/minissl'

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

    def inherited_ssl_listener(fd, ctx)
      if IS_JRUBY
        @events.error "SSL not supported on JRuby"
        raise UnsupportedOption
      end

      require 'puma/minissl'
      s = TCPServer.for_fd(fd)
      @ios << MiniSSL::Server.new(s, ctx)
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

        s = UNIXServer.new(path)
        @ios << s
      ensure
        File.umask old_mask
      end

      s
    end

    def inherit_unix_listener(path, fd)
      @unix_paths << path

      if fd.kind_of? TCPServer
        s = fd
      else
        s = UNIXServer.for_fd fd
      end
      @ios << s

      s
    end

  end
end
