module Puma
  class Binding
    include Puma::Const
    extend Forwardable

    def initialize(server)
      @server = server
      @path = server.path if unix?
    end

    attr_reader :server

    def to_s
      "#{protocol}://#{addrinfo_to_uri}"
    end

    def protocol
      if ssl?
        "ssl"
      elsif tcp?
        "tcp"
      elsif unix?
        "unix"
      end
    end

    def tcp?
      TCPServer === server
    end

    def ssl?
      defined?(MiniSSL::Server) && MiniSSL::Server === server
    end

    def unix?
      defined?(UNIXServer) && UNIXServer === server
    end

    def unlink_fd
      File.unlink(@path) if File.exist?(@path)
    end

    def env
      if unix?
        { REMOTE_ADDR => "127.0.0.1" }
      elsif ssl?
        { HTTPS_KEY => HTTPS }
      else
        {}
      end
    end

    def_delegators :@server, :close, :local_address, :no_tlsv1, :no_tlsv1_1

    private

    def addrinfo_to_uri
      if local_address.ipv6?
        "[#{local_address.ip_address}]:#{local_address.ip_port}"
      elsif local_address.ipv4?
        local_address.ip_unpack.join(':')
      elsif local_address.unix?
        local_address.unix_path
      end
    end
  end
end
