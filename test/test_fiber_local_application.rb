# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2023, by Samuel Williams.

require_relative "helper"

require "puma/server"

class FiberLocalApplication
  def call(env)
    # Just in case you didn't know, this is fiber local...
    count = (Thread.current[:request_count] ||= 0)
    Thread.current[:request_count] += 1
    [200, {"Content-Type" => "text/plain"}, [count.to_s]]
  end
end

class FiberLocalApplicationTest < Minitest::Test
  parallelize_me!

  def setup
    @tester = FiberLocalApplication.new
    @server = Puma::Server.new @tester, nil, {log_writer: Puma::LogWriter.strings, fiber_per_request: true}
    @port = (@server.add_tcp_listener "127.0.0.1", 0).addr[1]
    @tcp = "http://127.0.0.1:#{@port}"
    @server.run
  end

  def teardown
    @server.stop(true)
  end

  def test_empty_locals
    skip_if :oldwindows

    response = hit(["#{@tcp}/test"] * 3)
    assert_equal ["0", "0", "0"], response
  end
end
