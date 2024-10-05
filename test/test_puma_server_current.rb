# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2023, by Samuel Williams.

require_relative "helper"
require_relative "helpers/test_puma/puma_socket"

require "puma/server"

class PumaServerCurrentApplication
  def call(env)
    [200, {"Content-Type" => "text/plain"}, [Puma::Server.current.to_s]]
  end
end

class PumaServerCurrentTest < Minitest::Test
  parallelize_me!

  include TestPuma
  include TestPuma::PumaSocket

  def setup
    @tester = PumaServerCurrentApplication.new
    @server = Puma::Server.new @tester, nil, {log_writer: Puma::LogWriter.strings, clean_thread_locals: true}
    @bind_port = (@server.add_tcp_listener HOST, 0).addr[1]
    @server.run
  end

  def teardown
    @server.stop(true)
  end

  def test_clean_thread_locals
    server_string = @server.to_s
    responses = []

    # This must be a persistent connection to hit the `clean_thread_locals` code path.
    3.times { responses << send_http_read_resp_body }

    assert_equal [server_string]*3, responses
  end
end
