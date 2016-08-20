require 'websocket/driver'

module Puma
  module Websocket
    def self.detect?(env)
      ::WebSocket::Driver.websocket?(env)
    end

    class Connection
      def initialize(ws, handler)
        @ws = ws
        @handler = handler
      end

      def write(str)
        @ws.text str
      end

      def close
        @ws.close
      end
    end

    class Reactor
      def initialize(handler, ws, conn, req)
        @handler = handler
        @ws = ws
        @conn = conn
        @io = req.to_io
        @closed = false

        @lock = Mutex.new

        @events = []

        if handler.respond_to? :on_open
          ws.on :open, method(:queue)
        end

        if handler.respond_to? :on_message
          ws.on :message, method(:queue)
        end

        if handler.respond_to? :on_close
          ws.on :close do |ev|
            queue ev
            @closed = true
          end
        else
          ws.on :close do |ev|
            @closed = true
          end
        end
      end

      def to_io
        @io
      end

      def read_more
        begin
          data = @io.read_nonblock(1024)
        rescue Errno::EAGAIN
          return false
        rescue SystemCallError, IOError => e
          @ws.emit(:close,
                   ::WebSocket::Driver::CloseEvent.new(
                     "remote closed connection", 1011))
        else
          @ws.parse data
        end

        @lock.synchronize do
          return !@events.empty?
        end
      end

      def websocket?
        true
      end

      def closed?
        @closed
      end

      def queue(event)
        @lock.synchronize do
          @events << event
        end
      end

      def dispatch(event)
        case event
        when ::WebSocket::Driver::OpenEvent
          @handler.on_open @conn
        when ::WebSocket::Driver::CloseEvent
          @handler.on_close @conn
        when ::WebSocket::Driver::MessageEvent
          @handler.on_message @conn, event.data
        else
          STDERR.puts "Received unknown event for websockets: #{event.class}"
        end
      end

      def churn(pool)
        event = @lock.synchronize { @events.shift }
        return unless event

        dispatch event

        @lock.synchronize do
          pool << self unless @events.empty?
        end
      end

      def timeout_at
        false
      end

      def close
        @io.close
      end
    end

    class WS
      def initialize(req)
        @env = req.env
        @io = req.to_io
      end

      attr_reader :env

      def write(msg)
        @io.write msg
      end
    end

    def self.start(req, headers, handler, reactor)
      ws = ::WebSocket::Driver.rack(WS.new(req))

      headers.each do |k,v|
        if vs.respond_to?(:to_s)
          ws.set_header(k, vs.to_s)
        end
      end

      conn = Connection.new ws, handler
      rec = Reactor.new handler, ws, conn, req

      ws.on :ping do |ev|
        ws.pong ev
      end

      ws.start

      reactor.add rec

      :async
    end
  end
end
