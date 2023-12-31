# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2023, by Samuel Williams.

require_relative "helper"

require "puma/server"

class FiberStorageApplication
  def call(env)
    count = (Fiber[:request_count] ||= 0)
    Fiber[:request_count] += 1
    [200, {"Content-Type" => "text/plain"}, [count.to_s]]
  end
end

class FiberStorageApplicationTest < Minitest::Test
  parallelize_me!

  def setup
    skip "Fiber Storage is not supported on this Ruby" unless Fiber.respond_to?(:[])

    @tester = FiberStorageApplication.new
    @server = Puma::Server.new @tester, nil, {log_writer: Puma::LogWriter.strings, fiber_per_request: true}
    @port = (@server.add_tcp_listener "127.0.0.1", 0).addr[1]
    @tcp = "http://127.0.0.1:#{@port}"
    @server.run
  end

  def teardown
    @server.stop(true)
  end

  def test_empty_storage
    response = hit(["#{@tcp}/test"] * 3)
    assert_equal ["0", "0", "0"], response
  end
end
