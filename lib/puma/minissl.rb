module Puma
  module MiniSSL
    class Socket
      def initialize(socket, engine)
        @socket = socket
        @engine = engine
      end

      def to_io
        @socket
      end

      def readpartial(size)
        while true
          output = @engine.read
          return output if output

          data = @socket.readpartial(size)
          @engine.inject(data)
          output = @engine.read

          return output if output

          while neg_data = @engine.extract
            @socket.write neg_data
          end
        end
      end

      def engine_read_all
        output = @engine.read
        while output and additional_output = @engine.read
          output << additional_output
        end
        output
      end

      def read_nonblock(size)
        while true
          output = engine_read_all
          return output if output

          data = @socket.read_nonblock(size)

          @engine.inject(data)
          output = engine_read_all

          return output if output

          while neg_data = @engine.extract
            @socket.write neg_data
          end
        end
      end

      def write(data)
        need = data.bytesize

        while true
          wrote = @engine.write data
          enc = @engine.extract

          while enc
            @socket.write enc
            enc = @engine.extract
          end

          need -= wrote

          return data.bytesize if need == 0

          data = data[need..-1]
        end
      end

      alias_method :syswrite, :write

      def flush
        @socket.flush
      end

      def close
        @socket.close
      end

      def peeraddr
        @socket.peeraddr
      end
    end

    class Context
      attr_accessor :verify_mode

      attr_reader :key
      attr_reader :cert

      def key=(key)
        raise ArgumentError, "No such key file '#{key}'" unless File.exist? key
        @key = key
      end

      def cert=(cert)
        raise ArgumentError, "No such cert file '#{cert}'" unless File.exist? cert
        @cert = cert
      end
    end

    VERIFY_NONE = 0
    VERIFY_PEER = 1

    #if defined?(JRUBY_VERSION)
    #class Engine
    #def self.server(key, cert)
    #new(key, cert)
    #end
    #end
    #end

    class Server
      def initialize(socket, ctx)
        @socket = socket
        @ctx = ctx
      end

      def to_io
        @socket
      end

      def accept
        io = @socket.accept
        engine = Engine.server @ctx.key, @ctx.cert

        Socket.new io, engine
      end

      def accept_nonblock
        io = @socket.accept_nonblock
        engine = Engine.server @ctx.key, @ctx.cert

        Socket.new io, engine
      end

      def close
        @socket.close
      end
    end
  end
end
