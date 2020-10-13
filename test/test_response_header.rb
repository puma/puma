require_relative "helper"
require "puma/events"
require "net/http"

class TestResponseHeader < Minitest::Test
  parallelize_me!

  def setup
    @host = "127.0.0.1"

    @ios = []

    @app = ->(env) { [200, {}, [env['rack.url_scheme']]] }

    @events = Puma::Events.strings
    @server = Puma::Server.new @app, @events
  end

  def teardown
    @server.stop(true)
    @ios.each { |io| io.close if io && !io.closed? }
  end

  def server_run(app: @app, early_hints: false)
    @server.app = app
    @port = (@server.add_tcp_listener @host, 0).addr[1]
    @server.early_hints = true if early_hints
    @server.run
  end

  def send_http_and_read(req)
    send_http(req).read
  end

  def send_http(req)
    new_connection << req
  end

  def new_connection
    TCPSocket.new(@host, @port).tap {|sock| @ios << sock}
  end

  # The header keys must be Strings
  def test_integer_key
    server_run app: ->(env) { [200, { 1 => 'Boo'}, []] }
    data = send_http_and_read "GET / HTTP/1.0\r\n\r\n"

    assert_match(/HTTP\/1.1 500 Internal Server Error/, data)
  end

  # The header must respond to each
  def test_nil_header
    server_run app: ->(env) { [200, nil, []] }
    data = send_http_and_read "GET / HTTP/1.0\r\n\r\n"

    assert_match(/HTTP\/1.1 500 Internal Server Error/, data)
  end

  # The values of the header must be Strings
  def test_integer_value
    server_run app: ->(env) { [200, {'Content-Length' => 500}, []] }
    data = send_http_and_read "GET / HTTP/1.0\r\n\r\n"

    assert_match(/HTTP\/1.0 200 OK\r\nContent-Length: 500\r\n\r\n/, data)
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
    data = send_http_and_read "GET / HTTP/1.0\r\n\r\n"

    refute_match("#{name}: #{value}", data)
  end

  # The header must not contain a Status key.
  def test_status_key
    skip 'implement later'

    assert_ignore_header("Status", "500")
  end

  # Special headers starting “rack.” are for communicating with the server, and must not be sent back to the client.
  def test_rack_key
    skip 'implement later'

    assert_ignore_header("rack.command_to_server_only", "work")
  end


  # testing header key must conform rfc token specification
  # i.e. cannot contain non-printable ASCII, DQUOTE or “(),/:;<=>?@[]{}”.
  # Header keys will be set through two ways: Regular and early hints.

  def test_illegal_character_in_key
    skip 'implement later'
    assert_ignore_header("\"F\u0000o\u0025(@o}", "Boo")
  end

  def test_illegal_character_in_key_when_early_hints
    skip 'implement later'
    assert_ignore_header("\"F\u0000o\u0025(@o}", "Boo", early_hints: true)
  end

  # testing header value can be separated by \n into line, and each line must not contain characters below 037
  # Header values can be set through three ways: Regular, early hints and a special case for overriding content-length

  def test_illegal_character_in_value
    skip 'implement later'
    assert_ignore_header("X-header", "First \000Lin\037e")
  end

  def test_illegal_character_in_value_when_early_hints
    skip 'implement later'
    assert_ignore_header("X-header", "First \000Lin\037e", early_hints: true)
  end

  def test_illegal_character_in_value_when_override_content_length
    skip 'implement later'
    assert_ignore_header("Content-Length", "\037")
  end

  def test_illegal_character_in_value_when_newline
    skip 'implement later'

    server_run app: ->(env) { [200, {'X-header' => "First\000 line\nSecond Lin\037e"}, ["Hello"]] }
    data = send_http_and_read "GET / HTTP/1.0\r\n\r\n"

    refute_match("X-header: First\000 line\r\nX-header: Second Lin\037e\r\n", data)
  end
end
