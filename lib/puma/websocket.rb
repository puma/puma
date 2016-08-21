require 'websocket/driver'

module Puma
  module Websocket
    def self.detect?(env)
      ::WebSocket::Driver.websocket?(env)
    end

    class Connection
      def initialize(ws, handler, req)
        @ws = ws
        @handler = handler
        @req = req
      end

      def write(str)
        @ws.text str
      end

      def close
        @ws.close
      end

      def _activate(headers, reactor, pool)
        headers.each do |k,vs|
          if vs.respond_to?(:to_s)
            @ws.set_header(k, vs.to_s)
          end
        end

        rec = Reactor.new(@handler, @ws, self, @req)

        @ws.start

        if rec.read_more
          pool << rec
        end

        reactor.add rec
      end
    end

    module WriteMixin
      def write(msg)
        @_ws.text msg
      end

      def close
        @_ws.close
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
          # ok, no biggy.
        rescue SystemCallError, IOError
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
          @handler.on_open
        when ::WebSocket::Driver::CloseEvent
          @handler.on_close
        when ::WebSocket::Driver::MessageEvent
          @handler.on_message event.data
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

    def self.start(req, handler, options={})
      ws = ::WebSocket::Driver.rack(WS.new(req), options)

      conn = Connection.new ws, handler, req

      ws.on :ping do |ev|
        ws.pong ev
      end

      handler.extend WriteMixin
      handler.instance_variable_set :@_ws, ws

      conn
    end
  end
end
