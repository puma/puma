# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/test_puma/server_in_process"

require "puma/events"

class TestResponseHeader < TestPuma::ServerInProcess
  parallelize_me!

  # The header keys must be Strings
  def test_integer_key
    server_run app: ->(env) { [200, { 1 => 'Boo'}, []] }
    data = send_http_read_response GET_10

    assert_includes data, 'Puma caught this error'
  end

  # The header must respond to each
  def test_nil_header
    server_run app: ->(env) { [200, nil, []] }
    data = send_http_read_response GET_10

    assert_includes data, 'Puma caught this error'
  end

  # The values of the header must be Strings
  def test_integer_value
    server_run app: ->(env) { [200, {'Content-Length' => 500}, []] }
    data = send_http_read_response GET_10

    assert_includes data, "HTTP/1.0 200 OK\r\nContent-Length: 500\r\n\r\n"
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

    server_run app: app, early_hints: opts[:early_hints]
    data = send_http_read_response

    if opts[:early_hints]
      refute_includes data, "HTTP/1.1 103 Early Hints"
    end

    refute_includes data, "#{name}: #{value}"
  end

  # The header must not contain a Status key.
  def test_status_key
    assert_ignore_header("Status", "500")
  end

  # The header key can contain the word status.
  def test_key_containing_status
    server_run app: ->(env) { [200, {'Teapot-Status' => 'Boiling'}, []] }
    data = send_http_read_response GET_10

    assert_includes data, "HTTP/1.0 200 OK\r\nTeapot-Status: Boiling\r\nContent-Length: 0\r\n\r\n"
  end

  # Special headers starting “rack.” are for communicating with the server, and must not be sent back to the client.
  def test_rack_key
    assert_ignore_header("rack.command_to_server_only", "work")
  end

  # The header key can still start with the word rack
  def test_racket_key
    server_run app: ->(env) { [200, {'Racket' => 'Bouncy'}, []] }
    data = send_http_read_response GET_10

    assert_includes data, "HTTP/1.0 200 OK\r\nRacket: Bouncy\r\nContent-Length: 0\r\n\r\n"
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
    data = send_http_read_response GET_10

    refute_includes data, "X-header: First\000 line\r\nX-header: Second Lin\037e\r\n"
  end

  def test_header_value_array
    server_run app: ->(env) { [200, {'set-cookie' => ['z=1', 'a=2']}, ['Hello']] }
    data = send_http_read_response

    resp = "HTTP/1.1 200 OK\r\nset-cookie: z=1\r\nset-cookie: a=2\r\nContent-Length: 5\r\n\r\n"
    assert_includes data, resp
  end
end
