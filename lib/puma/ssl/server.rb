# frozen_string_literal: true

module Puma
  module SSL
    class Server
      def initialize(svr, ctx)
        @svr = svr
        @ctx = ctx
      end

      def to_io
        @svr
      end

      def accept_nonblock
        socket = @svr.accept_nonblock
        OpenSSL::SSL::SSLSocket.new(socket, @ctx)
        # At this point the client has connected/accepted at the socket layer but hasn't finished
        # the SSL handshake. We can't do a OpenSSL::SSL::SSLSocket#accept here because a slow client
        # would block other clients from connecting.
      end
    end
  end
end
