require_relative "helper"
require_relative "helpers/puma_socket"

require "puma/events"
require "net/http"
require "nio"

class TestResponseHeader < Minitest::Test
  parallelize_me!

  include PumaTest::PumaSocket

  def setup
    @host = "127.0.0.1"

    @app = ->(env) { [200, {}, [env['rack.url_scheme']]] }

    @log_writer = Puma::LogWriter.strings
    @server = Puma::Server.new @app, ::Puma::Events.new, {log_writer: @log_writer, min_threads: 1}
  end

  def teardown
    @server.stop(true)
  end

  def server_run(app: @app, early_hints: false)
    @server.app = app
    @port = (@server.add_tcp_listener @host, 0).addr[1]
    @server.instance_variable_set(:@early_hints, true) if early_hints
    @server.run
  end

  # The header keys must be Strings
  def test_integer_key
    server_run app: ->(env) { [200, { 1 => 'Boo'}, []] }
    resp = send_http_read_response "GET / HTTP/1.0\r\n\r\n"

    assert_match(/HTTP\/1.1 500 Internal Server Error/, resp)
  end

  # The header must respond to each
  def test_nil_header
    server_run app: ->(env) { [200, nil, []] }
    resp = send_http_read_response "GET / HTTP/1.0\r\n\r\n"

    assert_match(/HTTP\/1.1 500 Internal Server Error/, resp)
  end

  # The values of the header must be Strings
  def test_integer_value
    server_run app: ->(env) { [200, {'Content-Length' => 500}, []] }
    resp = send_http_read_response "GET / HTTP/1.0\r\n\r\n"

    assert_match(/HTTP\/1.0 200 OK\r\nContent-Length: 500\r\n\r\n/, resp)
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
    resp = send_http_read_response "GET / HTTP/1.0\r\n\r\n"

    refute_match("#{name}: #{value}", resp)
  end

  # The header must not contain a Status key.
  def test_status_key
    assert_ignore_header("Status", "500")
  end

  # The header key can contain the word status.
  def test_key_containing_status
    server_run app: ->(env) { [200, {'Teapot-Status' => 'Boiling'}, []] }
    resp = send_http_read_response "GET / HTTP/1.0\r\n\r\n"

    assert_match(/HTTP\/1.0 200 OK\r\nTeapot-Status: Boiling\r\nContent-Length: 0\r\n\r\n/, resp)
  end

  # Special headers starting “rack.” are for communicating with the server, and must not be sent back to the client.
  def test_rack_key
    assert_ignore_header("rack.command_to_server_only", "work")
  end

  # The header key can still start with the word rack
  def test_racket_key
    server_run app: ->(env) { [200, {'Racket' => 'Bouncy'}, []] }
    resp = send_http_read_response "GET / HTTP/1.0\r\n\r\n"

    assert_match(/HTTP\/1.0 200 OK\r\nRacket: Bouncy\r\nContent-Length: 0\r\n\r\n/, resp)
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
    resp = send_http_read_response "GET / HTTP/1.0\r\n\r\n"

    refute_match("X-header: First\000 line\r\nX-header: Second Lin\037e\r\n", resp)
  end

  def test_header_value_array
    server_run app: ->(env) { [200, {'set-cookie' => ['z=1', 'a=2']}, ['Hello']] }
    resp = send_http_read_response "GET / HTTP/1.1\r\n\r\n"

    expected = "HTTP/1.1 200 OK\r\nset-cookie: z=1\r\nset-cookie: a=2\r\nContent-Length: 5\r\n\r\nHello"
    assert_equal expected, resp
  end
end
