# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/test_puma/puma_socket"

require "puma/server"

class PumaClientCurrentTest < PumaTest
  parallelize_me!

  include TestPuma::PumaSocket

  def setup
    @host = "127.0.0.1"
    @in_app = false
    app = lambda do |_env|
      @in_app = true
      closed = Puma::Client.connection_closed?
      @in_app = false
      [200, {}, [closed.to_s]]
    end
    @server = Puma::Server.new app, nil, {log_writer: Puma::LogWriter.strings}
    @bind_port = (@server.add_tcp_listener @host, 0).addr[1]
    @server.run
  end

  def teardown
    @server.stop(true)
  end

  def test_connection_closed
    test = self
    @server.define_singleton_method(:closed_socket?) { |_socket| test.instance_variable_get(:@in_app) }

    assert_equal "true", send_http_read_resp_body
  end

  def test_connection_open
    @server.define_singleton_method(:closed_socket?) { |_socket| false }

    assert_equal "false", send_http_read_resp_body
  end

  def test_connection_closed_outside_request
    refute Puma::Client.connection_closed?
  end
end
