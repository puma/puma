# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2023, by Samuel Williams.

require_relative "helper"

require "puma/server"

class PumaServerCurrentApplication
  def call(env)
    [200, {"Content-Type" => "text/plain"}, [Puma::Server.current.to_s]]
  end
end

class PumaServerCurrentTest < Minitest::Test
  parallelize_me!

  def setup
    @tester = PumaServerCurrentApplication.new
    @server = Puma::Server.new @tester, nil, {log_writer: Puma::LogWriter.strings, clean_thread_locals: true}
    @port = (@server.add_tcp_listener "127.0.0.1", 0).addr[1]
    @tcp = "http://127.0.0.1:#{@port}"
    @url = URI.parse(@tcp)
    @server.run
  end

  def teardown
    @server.stop(true)
  end

  def test_clean_thread_locals
    server_string = @server.to_s
    responses = []

    # This must be a persistent connection to hit the `clean_thread_locals` code path.
    Net::HTTP.new(@url.host, @url.port).start do |connection|
      3.times do
        responses << connection.get("/").body
      end
    end

    assert_equal [server_string]*3, responses
  end
end
