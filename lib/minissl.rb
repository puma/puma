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

      p :start
      p :a1 => @engine.read

      p :w1 => @engine.output

      data = @socket.readpartial(size)

      p :data => data

      @engine.input data

      p :a2 => @engine.read
      p :w1 => @engine.output

      return

      while true
        output = @engine.read
        return output if output

        if IO.select([@socket], nil, nil, 1)
          data = @socket.readpartial(size)
          p :rp => [size, data.size, data]
          p :in => @engine.input(data)
        end
        output = @engine.read
        p :read => output
        return output if output

        neg_data = @engine.output
        p :neg => neg_data

        if neg_data
          @socket.write neg_data
        end
      end
    end

    def write(data)
      need = data.size

      while true
        wrote = @engine.write data
        enc = @engine.output

        if enc
          @socket.write enc
        end

        need -= wrote

        return data.size if need == 0

        data = data[need..-1]
      end
    end

    def flush
      @socket.flush
    end
  end

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
      engine = Engine.server @ctx[:key], @ctx[:cert]

      Socket.new io, engine
    end
  end
end
