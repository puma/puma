# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2024, by Samuel Williams.

require_relative "helper"

require "puma/server"

class RackProtocolApplication
  def call(env)
    if env['rack.protocol'].include?('echo')
      [200, {'rack.protocol' => 'echo'}, self.method(:echo)]
    end
  end

  def echo(stream)
    while line = stream.gets
      stream.write(line)
    end
  end
end

class RackProtocolApplicationTest < Minitest::Test
  parallelize_me!

  def setup
    @tester = RackProtocolApplication.new
    @server = Puma::Server.new @tester, nil, {log_writer: Puma::LogWriter.strings}
    @host = "127.0.0.1"
    @port = @server.add_tcp_listener(@host, 0).addr[1]
    @server.run
  end

  def teardown
    @server.stop(true)
  end

  def make_client
    TCPSocket.new(@host, @port)
  end

  def test_rack_protocol_valid
    client = make_client
    client.write "GET / HTTP/1.1\r\n" +
      "Host: localhost\r\n" +
      "Upgrade: echo\r\n" +
      "\r\n"

    assert_equal "HTTP/1.1 101 Switching Protocols\r\n", client.gets
    assert_equal "upgrade: echo\r\n", client.gets
    assert_equal "connection: upgrade\r\n", client.gets
    assert_equal "\r\n", client.gets

    client.write "hello world\n"
    assert_equal "hello world\n", client.gets
  ensure
    client.close
  end
end
