module Puma
  class TCPBinding < Binding
    def initialize(uri)
      super
      params = Util.parse_query uri.query
      # If +optimize_for_latency+ is true (the default) then clients connecting
      # will be optimized for latency over throughput.
      optimize_for_latency = params.key?('low_latency')
      # +backlog+ indicates how many unaccepted connections the kernel should
      # allow to accumulate before returning connection refused.
      backlog = params.fetch('backlog', 1024).to_i

      host = uri.host
      host = host[1..-2] if host and host[0..0] == '['
      @server = TCPServer.new(host, uri.port)
      if optimize_for_latency
        @server.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
      end
      @server.setsockopt(Socket::SOL_SOCKET,Socket::SO_REUSEADDR, true)
      @server.listen backlog
    end

    def env
      {}
    end

    def to_s
      "tcp://#{addrinfo_to_uri}"
    end

    def port
      @server.local_address.ip_port
    end

    private

    def addrinfo_to_uri
      return "unbound" if !@server
      if local_address.ipv6?
        "[#{local_address.ip_address}]:#{local_address.ip_port}"
      elsif local_address.ipv4?
        local_address.ip_unpack.join(':')
      end
    end
  end
end
