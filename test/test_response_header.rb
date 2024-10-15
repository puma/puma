# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/test_puma/puma_socket"

require "puma/events"
require "nio"

class TestResponseHeader < Minitest::Test
  parallelize_me!

  include TestPuma
  include TestPuma::PumaSocket

  # this file has limited response length, so 10kB works.
  CLIENT_SYSREAD_LENGTH = 10_240

  def setup
    @app = ->(env) { [200, {}, [env['rack.url_scheme']]] }

    @log_writer = Puma::LogWriter.strings
    @server = Puma::Server.new @app, ::Puma::Events.new, {log_writer: @log_writer, min_threads: 1}
  end

  def teardown
    @server.stop(true)
  end

  def server_run(app: @app, early_hints: false)
    @server.app = app
    @bind_port = (@server.add_tcp_listener HOST, 0).addr[1]
    @server.instance_variable_set(:@early_hints, true) if early_hints
    @server.run
  end

  # The header keys must be Strings
  def test_integer_key
    server_run app: ->(env) { [200, { 1 => 'Boo'}, []] }
    body = send_http_read_resp_body GET_10

    assert_start_with body, 'Puma caught this error'
  end

  # The header must respond to each
  def test_nil_header
    server_run app: ->(env) { [200, nil, []] }
    body = send_http_read_resp_body GET_10

    assert_start_with body, 'Puma caught this error'
  end

  # The values of the header must be Strings
  def test_integer_value
    server_run app: ->(env) { [200, {'Content-Length' => 500}, []] }
    response = send_http_read_response GET_10

    assert_start_with response, "HTTP/1.0 200 OK\r\nContent-Length: 500\r\n\r\n"
  end

  def assert_ignore_header(name, value, opts={})
    header = { name => value }

    if opts[:early_hints]
      app = ->(env) do
        env['rack.early_hints'].call(header)
        [200, {}, ['Hello']]
      end
    else
      app = -> (env) { [200, header, ['hello']]}
    end

    server_run(app: app, early_hints: opts[:early_hints])
    response = send_http_read_response GET_10

    if opts[:early_hints]
      refute_includes response, "HTTP/1.1 103 Early Hints"
    end

    refute_includes response, "#{name}: #{value}"
  end

  # The header must not contain a Status key.
  def test_status_key
    assert_ignore_header("Status", "500")
  end

  # The header key can contain the word status.
  def test_key_containing_status
    server_run app: ->(env) { [200, {'Teapot-Status' => 'Boiling'}, []] }
    response = send_http_read_response "GET / HTTP/1.0\r\n\r\n"

    assert_equal "HTTP/1.0 200 OK\r\nTeapot-Status: Boiling\r\nContent-Length: 0\r\n\r\n", response
  end

  # Special headers starting “rack.” are for communicating with the server, and must not be sent back to the client.
  def test_rack_key
    assert_ignore_header("rack.command_to_server_only", "work")
  end

  # The header key can still start with the word rack
  def test_racket_key
    server_run app: ->(env) { [200, {'Racket' => 'Bouncy'}, []] }
    response = send_http_read_response GET_10

    assert_equal "HTTP/1.0 200 OK\r\nRacket: Bouncy\r\nContent-Length: 0\r\n\r\n", response
  end

  # testing header key must conform rfc token specification
  # i.e. cannot contain non-printable ASCII, DQUOTE or “(),/:;<=>?@[]{}”.
  # Header keys will be set through two ways: Regular and early hints.

  def test_illegal_character_in_key
    assert_ignore_header("\"F\u0000o\u0025(@o}", "Boo")
  end

  def test_illegal_character_in_key_when_early_hints
    assert_ignore_header("\"F\u0000o\u0025(@o}", "Boo", early_hints: true)
  end

  # testing header value can be separated by \n into line, and each line must not contain characters below 037
  # Header values can be set through three ways: Regular, early hints and a special case for overriding content-length

  def test_illegal_character_in_value
    assert_ignore_header("X-header", "First \000Lin\037e")
  end

  def test_illegal_character_in_value_when_early_hints
    assert_ignore_header("X-header", "First \000Lin\037e", early_hints: true)
  end

  def test_illegal_character_in_value_when_override_content_length
    assert_ignore_header("Content-Length", "\037")
  end

  def test_illegal_character_in_value_when_newline
    server_run app: ->(env) { [200, {'X-header' => "First\000 line\nSecond Lin\037e"}, ["Hello"]] }
    response = send_http_read_response GET_10

    refute_match("X-header: First\000 line\r\nX-header: Second Lin\037e\r\n", response)
  end

  def test_header_value_array
    server_run app: ->(env) { [200, {'set-cookie' => ['z=1', 'a=2']}, ['Hello']] }
    response = send_http_read_response

    resp = "HTTP/1.1 200 OK\r\nset-cookie: z=1\r\nset-cookie: a=2\r\nContent-Length: 5\r\n\r\n"
    assert_start_with response, resp
  end
end
