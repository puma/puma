require_relative "helper"

class TestPumaServer < Minitest::Test

  def setup
    @port = 0
    @host = "127.0.0.1"

    @app = lambda { |env| [200, {}, [env['rack.url_scheme']]] }

    @events = Puma::Events.new STDOUT, STDERR
    @server = Puma::Server.new @app, @events
  end

  def teardown
    @server.stop(true)
  end

  def server_run(app: @app, early_hints: false)
    @server.app = app
    @server.add_tcp_listener @host, @port
    @server.early_hints = true if early_hints
    @server.run
  end

  def header(sock)
    header = []
    while true
      line = sock.gets
      break if line == "\r\n"
      header << line.strip
    end

    header
  end

  def send_http_and_read(req)
    port = @server.connected_port
    sock = TCPSocket.new @host, port
    sock << req
    sock.read
  end

  def test_proper_stringio_body
    data = nil

    @server.app = proc do |env|
      data = env['rack.input'].read
      [200, {}, ["ok"]]
    end

    @server.add_tcp_listener @host, @port
    @server.run

    fifteen = "1" * 15

    sock = TCPSocket.new @host, @server.connected_port
    sock << "PUT / HTTP/1.0\r\nContent-Length: 30\r\n\r\n#{fifteen}"
    sleep 0.1 # important so that the previous data is sent as a packet
    sock << fifteen

    sock.read

    assert_equal "#{fifteen}#{fifteen}", data
  end

  def test_puma_socket
    body = "HTTP/1.1 750 Upgraded to Awesome\r\nDone: Yep!\r\n"
    @server.app = proc do |env|
      io = env['puma.socket']

      io.write body

      io.close

      [-1, {}, []]
    end

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "PUT / HTTP/1.0\r\n\r\nHello"

    assert_equal body, sock.read
  end

  def test_very_large_return
    giant = "x" * 2056610

    @server.app = proc do |env|
      [200, {}, [giant]]
    end

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "GET / HTTP/1.0\r\n\r\n"

    while true
      line = sock.gets
      break if line == "\r\n"
    end

    out = sock.read

    assert_equal giant.bytesize, out.bytesize
  end

  def test_respect_x_forwarded_proto
    @server.app = proc do |env|
      [200, {}, [env['SERVER_PORT']]]
    end

    @server.add_tcp_listener @host, @port
    @server.run

    req = Net::HTTP::Get.new("/")
    req['HOST'] = "example.com"
    req['X_FORWARDED_PROTO'] = "https"

    res = Net::HTTP.start @host, @server.connected_port do |http|
      http.request(req)
    end

    assert_equal "443", res.body
  end

  def test_default_server_port
    @server.app = proc do |env|
      [200, {}, [env['SERVER_PORT']]]
    end

    @server.add_tcp_listener @host, @port
    @server.run

    req = Net::HTTP::Get.new("/")
    req['HOST'] = "example.com"
    req['X-FORWARDED-PROTO'] = "https,http"

    res = Net::HTTP.start @host, @server.connected_port do |http|
      http.request(req)
    end

    assert_equal "80", res.body
  end

  def test_HEAD_has_no_body
    @server.app = proc { |env| [200, {"Foo" => "Bar"}, ["hello"]] }

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "HEAD / HTTP/1.0\r\n\r\n"

    data = sock.read

    assert_equal "HTTP/1.0 200 OK\r\nFoo: Bar\r\nContent-Length: 5\r\n\r\n", data
  end

  def test_GET_with_empty_body_has_sane_chunking
    @server.app = proc { |env| [200, {}, [""]] }

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "HEAD / HTTP/1.0\r\n\r\n"

    data = sock.read

    assert_equal "HTTP/1.0 200 OK\r\nContent-Length: 0\r\n\r\n", data
  end

  def test_early_hints_works
    @server.app = proc { |env|
     env['rack.early_hints'].call("Link" => "</style.css>; rel=preload; as=style\n</script.js>; rel=preload")
     [200, { "X-Hello" => "World" }, ["Hello world!"]]
    }

    @server.add_tcp_listener @host, @port
    @server.early_hints = true
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "HEAD / HTTP/1.0\r\n\r\n"

    data = sock.read

    expected_data = (<<EOF
HTTP/1.1 103 Early Hints
Link: </style.css>; rel=preload; as=style
Link: </script.js>; rel=preload

HTTP/1.0 200 OK
X-Hello: World
Content-Length: 12
EOF
).split("\n").join("\r\n") + "\r\n\r\n"

    assert_equal true, @server.early_hints
    assert_equal expected_data, data
  end

  def test_early_hints_is_off_by_default
    @server.app = proc { |env|
     assert_nil env['rack.early_hints']
     [200, { "X-Hello" => "World" }, ["Hello world!"]]
    }

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "HEAD / HTTP/1.0\r\n\r\n"

    data = sock.read

    expected_data = (<<EOF
HTTP/1.0 200 OK
X-Hello: World
Content-Length: 12
EOF
).split("\n").join("\r\n") + "\r\n\r\n"

    assert_nil @server.early_hints
    assert_equal expected_data, data
  end

  def test_GET_with_no_body_has_sane_chunking
    @server.app = proc { |env| [200, {}, []] }

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "HEAD / HTTP/1.0\r\n\r\n"

    data = sock.read

    assert_equal "HTTP/1.0 200 OK\r\n\r\n", data
  end

  def test_doesnt_print_backtrace_in_production
    @events = Puma::Events.strings
    @server = Puma::Server.new @app, @events

    @server.app = proc { |e| raise "don't leak me bro" }
    @server.leak_stack_on_error = false
    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "GET / HTTP/1.0\r\n\r\n"

    data = sock.read

    refute_match(/don't leak me bro/, data)
    assert_match(/HTTP\/1.0 500 Internal Server Error/, data)
  end

  def test_prints_custom_error
    @events = Puma::Events.strings
    re = lambda { |err| [302, {'Content-Type' => 'text', 'Location' => 'foo.html'}, ['302 found']] }
    @server = Puma::Server.new @app, @events, {:lowlevel_error_handler => re}

    @server.app = proc { |e| raise "don't leak me bro" }
    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "GET / HTTP/1.0\r\n\r\n"

    data = sock.read
    assert_match(/HTTP\/1.0 302 Found/, data)
  end

  def test_leh_gets_env_as_well
    @events = Puma::Events.strings
    re = lambda { |err,env|
      env['REQUEST_PATH'] || raise("where is env?")
      [302, {'Content-Type' => 'text', 'Location' => 'foo.html'}, ['302 found']]
    }

    @server = Puma::Server.new @app, @events, {:lowlevel_error_handler => re}

    @server.app = proc { |e| raise "don't leak me bro" }
    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "GET / HTTP/1.0\r\n\r\n"

    data = sock.read
    assert_match(/HTTP\/1.0 302 Found/, data)
  end

  def test_custom_http_codes_10
    @server.app = proc { |env| [449, {}, [""]] }

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port

    sock << "GET / HTTP/1.0\r\n\r\n"

    data = sock.read

    assert_equal "HTTP/1.0 449 CUSTOM\r\nContent-Length: 0\r\n\r\n", data
  end

  def test_custom_http_codes_11
    @server.app = proc { |env| [449, {}, [""]] }

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "GET / HTTP/1.1\r\nConnection: close\r\n\r\n"

    data = sock.read

    assert_equal "HTTP/1.1 449 CUSTOM\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
  end

  def test_HEAD_returns_content_headers
    @server.app = proc { |env| [200, {"Content-Type" => "application/pdf",
                                      "Content-Length" => "4242"}, []] }

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port

    sock << "HEAD / HTTP/1.0\r\n\r\n"

    data = sock.read

    assert_equal "HTTP/1.0 200 OK\r\nContent-Type: application/pdf\r\nContent-Length: 4242\r\n\r\n", data
  end

  def test_status_hook_fires_when_server_changes_states

    states = []

    @events.register(:state) { |s| states << s }

    @server.app = proc { |env| [200, {}, [""]] }

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "HEAD / HTTP/1.0\r\n\r\n"

    sock.read

    assert_equal [:booting, :running], states

    @server.stop(true)

    assert_equal [:booting, :running, :stop, :done], states
  end

  def test_timeout_in_data_phase
    @server.first_data_timeout = 2
    @server.add_tcp_listener @host, @port
    @server.run

    client = TCPSocket.new @host, @server.connected_port

    client << "POST / HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\n"

    data = client.gets

    assert_equal "HTTP/1.1 408 Request Timeout\r\n", data
  end

  def test_http_11_keep_alive_with_body
    @server.app = proc { |env| [200, {"Content-Type" => "plain/text"}, ["hello\n"]] }

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "GET / HTTP/1.1\r\nConnection: Keep-Alive\r\n\r\n"

    h = header(sock)

    body = sock.gets

    assert_equal ["HTTP/1.1 200 OK", "Content-Type: plain/text", "Content-Length: 6"], h
    assert_equal "hello\n", body

    sock.close
  end

  def test_http_11_close_with_body
    @server.app = proc { |env| [200, {"Content-Type" => "plain/text"}, ["hello"]] }

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "GET / HTTP/1.1\r\nConnection: close\r\n\r\n"

    data = sock.read

    assert_equal "HTTP/1.1 200 OK\r\nContent-Type: plain/text\r\nConnection: close\r\nContent-Length: 5\r\n\r\nhello", data
  end

  def test_http_11_keep_alive_without_body
    @server.app = proc { |env| [204, {}, []] }

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "GET / HTTP/1.1\r\nConnection: Keep-Alive\r\n\r\n"

    h = header(sock)

    sock.close

    assert_equal ["HTTP/1.1 204 No Content"], h
  end

  def test_http_11_close_without_body
    @server.app = proc { |env| [204, {}, []] }

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "GET / HTTP/1.1\r\nConnection: close\r\n\r\n"

    h = header(sock)

    sock.close

    assert_equal ["HTTP/1.1 204 No Content", "Connection: close"], h
  end

  def test_http_10_keep_alive_with_body
    @server.app = proc { |env| [200, {"Content-Type" => "plain/text"}, ["hello\n"]] }

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "GET / HTTP/1.0\r\nConnection: Keep-Alive\r\n\r\n"

    h = header(sock)

    body = sock.gets

    assert_equal ["HTTP/1.0 200 OK", "Content-Type: plain/text", "Connection: Keep-Alive", "Content-Length: 6"], h
    assert_equal "hello\n", body

    sock.close
  end

  def test_http_10_close_with_body
    @server.app = proc { |env| [200, {"Content-Type" => "plain/text"}, ["hello"]] }

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "GET / HTTP/1.0\r\nConnection: close\r\n\r\n"

    data = sock.read

    assert_equal "HTTP/1.0 200 OK\r\nContent-Type: plain/text\r\nContent-Length: 5\r\n\r\nhello", data
  end

  def test_http_10_partial_hijack_with_content_length
    body_parts = ['abc', 'de']

    @server.app = proc do |env|
      hijack_lambda = proc do | io |
        io.write(body_parts[0])
        io.write(body_parts[1])
        io.close
      end
      [200, {"Content-Length" => "5", 'rack.hijack' => hijack_lambda}, nil]
    end

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "GET / HTTP/1.0\r\nConnection: close\r\n\r\n"

    data = sock.read

    assert_equal "HTTP/1.0 200 OK\r\nContent-Length: 5\r\n\r\nabcde", data
  end

  def test_http_10_keep_alive_without_body
    @server.app = proc { |env| [204, {}, []] }

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "GET / HTTP/1.0\r\nConnection: Keep-Alive\r\n\r\n"

    h = header(sock)

    assert_equal ["HTTP/1.0 204 No Content", "Connection: Keep-Alive"], h

    sock.close
  end

  def test_http_10_close_without_body
    @server.app = proc { |env| [204, {}, []] }

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "GET / HTTP/1.0\r\nConnection: close\r\n\r\n"

    data = sock.read

    assert_equal "HTTP/1.0 204 No Content\r\n\r\n", data
  end

  def test_Expect_100
    @server.app = proc { |env| [200, {}, [""]] }

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "GET / HTTP/1.1\r\nConnection: close\r\nExpect: 100-continue\r\n\r\n"

    data = sock.read

    assert_equal "HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
  end

  def test_chunked_request
    body = nil
    @server.app = proc { |env|
      body = env['rack.input'].read
      [200, {}, [""]]
    }

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "GET / HTTP/1.1\r\nConnection: close\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nh\r\n4\r\nello\r\n0\r\n"

    data = sock.read

    assert_equal "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
    assert_equal "hello", body
  end

  def test_chunked_request_pause_before_value
    body = nil
    @server.app = proc { |env|
      body = env['rack.input'].read
      [200, {}, [""]]
    }

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "GET / HTTP/1.1\r\nConnection: close\r\nTransfer-Encoding: chunked\r\n\r\n1\r\n"
    sleep 1

    sock << "h\r\n4\r\nello\r\n0\r\n"

    data = sock.read

    assert_equal "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
    assert_equal "hello", body
  end

  def test_chunked_request_pause_between_chunks
    body = nil
    @server.app = proc { |env|
      body = env['rack.input'].read
      [200, {}, [""]]
    }

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "GET / HTTP/1.1\r\nConnection: close\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nh\r\n"
    sleep 1

    sock << "4\r\nello\r\n0\r\n"

    data = sock.read

    assert_equal "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
    assert_equal "hello", body
  end

  def test_chunked_request_pause_mid_count
    body = nil
    @server.app = proc { |env|
      body = env['rack.input'].read
      [200, {}, [""]]
    }

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "GET / HTTP/1.1\r\nConnection: close\r\nTransfer-Encoding: chunked\r\n\r\n1\r"
    sleep 1

    sock << "\nh\r\n4\r\nello\r\n0\r\n"

    data = sock.read

    assert_equal "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
    assert_equal "hello", body
  end

  def test_chunked_request_pause_before_count_newline
    body = nil
    @server.app = proc { |env|
      body = env['rack.input'].read
      [200, {}, [""]]
    }

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "GET / HTTP/1.1\r\nConnection: close\r\nTransfer-Encoding: chunked\r\n\r\n1"
    sleep 1

    sock << "\r\nh\r\n4\r\nello\r\n0\r\n"

    data = sock.read

    assert_equal "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
    assert_equal "hello", body
  end

  def test_chunked_request_pause_mid_value
    body = nil
    @server.app = proc { |env|
      body = env['rack.input'].read
      [200, {}, [""]]
    }

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "GET / HTTP/1.1\r\nConnection: close\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nh\r\n4\r\ne"
    sleep 1

    sock << "llo\r\n0\r\n"

    data = sock.read

    assert_equal "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
    assert_equal "hello", body
  end

  def test_chunked_request_header_case
    body = nil
    @server.app = proc { |env|
      body = env['rack.input'].read
      [200, {}, [""]]
    }

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "GET / HTTP/1.1\r\nConnection: close\r\nTransfer-Encoding: Chunked\r\n\r\n1\r\nh\r\n4\r\nello\r\n0\r\n"

    data = sock.read

    assert_equal "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
    assert_equal "hello", body
  end

  def test_chunked_keep_alive
    body = nil
    @server.app = proc { |env|
      body = env['rack.input'].read
      [200, {}, [""]]
    }

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "GET / HTTP/1.1\r\nConnection: Keep-Alive\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nh\r\n4\r\nello\r\n0\r\n\r\n"

    h = header(sock)

    assert_equal ["HTTP/1.1 200 OK", "Content-Length: 0"], h
    assert_equal "hello", body

    sock.close
  end

  def test_chunked_keep_alive_two_back_to_back
    body = nil
    @server.app = proc { |env|
      body = env['rack.input'].read
      [200, {}, [""]]
    }

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port
    sock << "GET / HTTP/1.1\r\nConnection: Keep-Alive\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nh\r\n4\r\nello\r\n0\r\n\r\n"

    h = header(sock)
    assert_equal ["HTTP/1.1 200 OK", "Content-Length: 0"], h
    assert_equal "hello", body

    sock << "GET / HTTP/1.1\r\nConnection: Keep-Alive\r\nTransfer-Encoding: chunked\r\n\r\n4\r\ngood\r\n3\r\nbye\r\n0\r\n\r\n"
    sleep 0.1

    h = header(sock)

    assert_equal ["HTTP/1.1 200 OK", "Content-Length: 0"], h
    assert_equal "goodbye", body

    sock.close
  end

  def test_empty_header_values
    @server.app = proc { |env| [200, {"X-Empty-Header" => ""}, []] }

    @server.add_tcp_listener @host, @port
    @server.run

    sock = TCPSocket.new @host, @server.connected_port

    sock << "HEAD / HTTP/1.0\r\n\r\n"

    data = sock.read

    assert_equal "HTTP/1.0 200 OK\r\nX-Empty-Header: \r\n\r\n", data
  end

  # Rack may pass a newline in a header expecting us to split it.
  def test_newline_splits
    server_run app: ->(_) { [200, {'X-header' => "first line\nsecond line"}, ["Hello"]] }

    data = send_http_and_read "HEAD / HTTP/1.0\r\n\r\n"

    assert_match "X-header: first line\r\nX-header: second line\r\n", data
  end

  def test_newline_splits_in_early_hint
    server_run early_hints: true, app: ->(env) do
      env['rack.early_hints'].call({'X-header' => "first line\nsecond line"})
      [200, {}, ["Hello world!"]]
    end

    data = send_http_and_read "HEAD / HTTP/1.0\r\n\r\n"

    assert_match "X-header: first line\r\nX-header: second line\r\n", data
  end

  # To comply with the Rack spec, we have to split header field values
  # containing newlines into multiple headers.
  def assert_does_not_allow_http_injection(app, opts = {})
    server_run(early_hints: opts[:early_hints], app: app)

    data = send_http_and_read "HEAD / HTTP/1.0\r\n\r\n"

    refute_match(/[\r\n]Cookie: hack[\r\n]/, data)
  end

  # HTTP Injection Tests
  #
  # Puma should prevent injection of CR and LF characters into headers, either as
  # CRLF or CR or LF, because browsers may interpret it at as a line end and
  # allow untrusted input in the header to split the header or start the
  # response body. While it's not documented anywhere and they shouldn't be doing
  # it, Chrome and curl recognize a lone CR as a line end. According to RFC,
  # clients SHOULD interpret LF as a line end for robustness, and CRLF is the
  # specced line end.
  #
  # There are three different tests because there are three ways to set header
  # content in Puma. Regular (rack env), early hints, and a special case for
  # overriding content-length.
  {"cr" => "\r", "lf" => "\n", "crlf" => "\r\n"}.each do |suffix, line_ending|
    # The cr-only case for the following test was CVE-2020-5247
    define_method("test_prevent_response_splitting_headers_#{suffix}") do
      app = ->(_) { [200, {'X-header' => "untrusted input#{line_ending}Cookie: hack"}, ["Hello"]] }
      assert_does_not_allow_http_injection(app)
    end

    define_method("test_prevent_response_splitting_headers_early_hint_#{suffix}") do
      app = ->(env) do
        env['rack.early_hints'].call("X-header" => "untrusted input#{line_ending}Cookie: hack")
        [200, {}, ["Hello"]]
      end
      assert_does_not_allow_http_injection(app, early_hints: true)
    end

    define_method("test_prevent_content_length_injection_#{suffix}") do
      app = ->(_) { [200, {'content-length' => "untrusted input#{line_ending}Cookie: hack"}, ["Hello"]] }
      assert_does_not_allow_http_injection(app)
    end
  end
end
