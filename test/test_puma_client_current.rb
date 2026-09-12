# frozen_string_literal: true

require_relative "helper"

require "puma/server"

class PumaClientCurrentApplication
  def initialize
    @around = nil
    @responses = []
  end

  attr_accessor :around
  attr_reader :responses

  def call(env)
    @around.call do
      body = Puma::Client.connection_closed? ? "closed" : "open"
      @responses << body
      [200, {"Content-Type" => "text/plain"}, [body]]
    end
  end
end

class PumaClientCurrentTest < PumaTest
  parallelize_me!

  def setup
    @tester = PumaClientCurrentApplication.new
    @server = Puma::Server.new @tester, nil, {log_writer: Puma::LogWriter.strings}
    @port = (@server.add_tcp_listener "127.0.0.1", 0).addr[1]
    @tcp = "http://127.0.0.1:#{@port}"
    @url = URI.parse(@tcp)
    @server.run
  end

  def teardown
    @server.stop(true)
  end

  def test_connection_closed
    skip_unless :closed_socket

    def get(disconnect:)
      # Make an unretriable request where the socket is optionally closed before the app handler runs.
      @tester.around = nil # these should all be called sequentially, so cause an error if called out of sequence.
      Net::HTTP.new(@url.host, @url.port).start do |connection|
        connection.max_retries = 0
        socket = connection.instance_variable_get(:@socket)
        waiter = Thread.new { Thread.stop }
        @tester.around = proc do |&handle_request|
          socket.close if disconnect
          handle_request.call
          waiter.wakeup
        end
        body = connection.get("/").body
        waiter.join
        body
      rescue IOError # expected if disconnect is true
        raise unless disconnect
      end
    end

    3.times { get(disconnect: false) }
    3.times { get(disconnect: true) }
    3.times { get(disconnect: false) }

    assert_equal ["open"]*3 + ["closed"]*3 + ["open"]*3, @tester.responses
  end
end
