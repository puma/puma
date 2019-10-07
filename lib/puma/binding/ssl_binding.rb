module Puma
  class SSLBinding < TCPBinding
    def initialize(uri, ctx: nil)
      super
      params = Util.parse_query uri.query
      require 'puma/minissl'

      MiniSSL.check

      ctx = MiniSSL::ContextBuilder.call(params) unless ctx

      # See implementation at TCPBinding#initialize
      @server = MiniSSL::Server.new @server, ctx
    end

    def env
      { HTTPS_KEY => HTTPS }
    end

    def to_s
      "ssl://#{addrinfo_to_uri}"
    end
  end
end
