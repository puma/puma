require_relative "helper"

require "puma/puma_http11"

class TestWebsocketIntegration < Minitest::Test
  class WebsocketClient
    def initialize(host, port)
      @url = "ws://#{host}:#{port}"

      @host = host
      @port = port
    end

    def connect
      socket = TCPSocket.new @host, @port
      socket.instance_eval do
        def url
          @url
        end
      end
      socket.instance_variable_set :@url, "ws://#{@host}:#{@port}/"

      @driver = WebSocket::Driver.client socket
      @driver.start

      # driver.on(:open)    { |event| on_open(event) }
      # driver.on(:message) { |event| on_message(event) }
      # driver.on(:close)   { |event| @dead = true; on_close(event) }

      # Wait for server full response
      loop do
        line = socket.gets
        @driver.parse line
        break if line == "\r\n"
      end

      # Spawn a thread to read server messages before returning
      @thread = Thread.new do
        begin
          until @dead
            byte = socket.read_nonblock 1
            driver.parse byte
          end
        rescue Errno::EAGAIN
          sleep 0.1
          retry
        end
      end
    end

    def send_text(message)
      @driver.text message
    end

    def send_binary(message)
      @driver.binary message
    end

    def close
      @dead = true
      @thread.join
    end

    # def on_open(); end
    # def on_message(); end
    # def on_close(); end
  end

  def setup
    app = Object.new
    app.instance_eval do
      def call(env)
        if env['rack.upgrade?'] == :websocket
          env['rack.upgrade'] = self
          [101, {}, []]
        else
          [404, {}, ["call as a websocket"]]
        end
      end
    end

    @port = 0
    @host = "127.0.0.1"

    @server = Puma::Server.new app
  end

  def teardown
    @server.stop(true)
  end

  # Because the reactor is running in another thread, we may need to wait
  # until the hooks are called. I wish we had a better way to do this,
  # suggestions are very welcome.
  def wait_until(timeout = 1)
    begin
      Timeout.timeout(timeout) do
        sleep 0.01 until yield
      end
    rescue Timeout::Error
    end
  end

  def test_on_open_hook
    @server.app.instance_eval do
      def on_open_called
        @on_open_called
      end

      def on_open(*args)
        @on_open_called = *args
      end
    end

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << [
      "GET / HTTP/1.0",
      "Connection: Upgrade",
      "Upgrade: websocket",
      "Sec-WebSocket-Version: 13",
      "Sec-WebSocket-Key: qHbygOE6qqdhGEhNN1/bpQ==",
      "\r\n"
    ].join("\r\n")
    sock.close

    wait_until { @server.app.on_open_called }

    assert @server.app.on_open_called, "Expected on_open to be called"

    connection, = @server.app.on_open_called
    assert_instance_of Puma::Websocket::Connection, connection
  end

  def test_on_message_hook
    @server.app.instance_eval do
      def on_message_calls
        @on_message_calls
      end

      def on_message(*args)
        @on_message_calls ||= []
        @on_message_calls << args
      end
    end

    @server.add_tcp_listener @host, @server.connected_port
    @server.run

    client = WebsocketClient.new @host, @server.connected_port
    client.connect

    client.send_text "hey!"
    client.close

    wait_until { @server.app.on_message_calls }
    assert_equal 1, @server.app.on_message_calls.size

    connection, message = @server.app.on_message_calls.first
    assert_instance_of Puma::Websocket::Connection, connection
    assert_equal "hey!", message
  end

  def test_on_close_hook
    @server.app.instance_eval do
      def on_close_called
        @on_close_called
      end

      def on_close(*args)
        @on_close_called = *args
      end
    end

    @server.add_tcp_listener @host, @server.connected_port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << [
      "GET / HTTP/1.0",
      "Connection: Upgrade",
      "Upgrade: websocket",
      "Sec-WebSocket-Version: 13",
      "Sec-WebSocket-Key: qHbygOE6qqdhGEhNN1/bpQ==",
      "\r\n"
    ].join("\r\n")
    sock.close

    wait_until { @server.app.on_close_called }
    assert @server.app.on_close_called, "Expected on_close to be called"

    connection, = @server.app.on_close_called
    assert_instance_of Puma::Websocket::Connection, connection
  end
end
