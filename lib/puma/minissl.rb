module Puma::MiniSSL
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

    def read_nonblock(size)
      while true
        output = @engine.read
        return output if output

        data = @socket.read_nonblock(size)

        @engine.inject(data)
        output = @engine.read

        return output if output

        while neg_data = @engine.extract
          @socket.write neg_data
        end
      end
    end

    def write(data)
      need = data.size

      while true
        wrote = @engine.write data
        enc = @engine.extract

        if enc
          @socket.syswrite enc
        end

        need -= wrote

        return data.size if need == 0

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
    attr_accessor :key, :cert, :verify_mode
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
