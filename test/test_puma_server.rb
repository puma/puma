require_relative "helper"

class TestPumaServer < Minitest::Test
  parallelize_me!

  def setup
    @port = 0
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
    sock = TCPSocket.new @host, @server.connected_port
    @ios << sock
    sock << req
    sock.read
  end

  def send_http(req)
    sock = TCPSocket.new @host, @server.connected_port
    @ios << sock
    sock << req
    sock
  end

  def test_proper_stringio_body
    data = nil

    server_run app: ->(env) do
      data = env['rack.input'].read
      [200, {}, ["ok"]]
    end

    fifteen = "1" * 15

    sock = send_http "PUT / HTTP/1.0\r\nContent-Length: 30\r\n\r\n#{fifteen}"

    sleep 0.1 # important so that the previous data is sent as a packet
    sock << fifteen

    sock.read

    assert_equal "#{fifteen}#{fifteen}", data
  end

  def test_puma_socket
    body = "HTTP/1.1 750 Upgraded to Awesome\r\nDone: Yep!\r\n"
    server_run app: ->(env) do
      io = env['puma.socket']
      io.write body
      io.close
      [-1, {}, []]
    end

    data = send_http_and_read "PUT / HTTP/1.0\r\n\r\nHello"

    assert_equal body, data
  end

  def test_very_large_return
    giant = "x" * 2056610

    server_run app: ->(env) do
      [200, {}, [giant]]
    end

    sock = send_http "GET / HTTP/1.0\r\n\r\n"

    while true
      line = sock.gets
      break if line == "\r\n"
    end

    out = sock.read

    assert_equal giant.bytesize, out.bytesize
  end

  def test_respect_x_forwarded_proto
    env = {}
    env['HOST'] = "example.com"
    env['HTTP_X_FORWARDED_PROTO'] = "https,http"

    assert_equal "443", @server.default_server_port(env)
  end

  def test_respect_x_forwarded_ssl_on
    env = {}
    env['HOST'] = 'example.com'
    env['HTTP_X_FORWARDED_SSL'] = 'on'

    assert_equal "443", @server.default_server_port(env)
  end

  def test_respect_x_forwarded_scheme
    env = {}
    env['HOST'] = 'example.com'
    env['HTTP_X_FORWARDED_SCHEME'] = 'https'

    assert_equal '443', @server.default_server_port(env)
  end

  def test_default_server_port
    server_run app: ->(env) do
      [200, {}, [env['SERVER_PORT']]]
    end

    req = Net::HTTP::Get.new '/'
    req['HOST'] = 'example.com'

    res = Net::HTTP.start @host, @server.connected_port do |http|
      http.request(req)
    end

    assert_equal "80", res.body
  end

  def test_default_server_port_respects_x_forwarded_proto
    server_run app: ->(env) do
      [200, {}, [env['SERVER_PORT']]]
    end

    req = Net::HTTP::Get.new("/")
    req['HOST'] = "example.com"
    req['X_FORWARDED_PROTO'] = "https,http"

    res = Net::HTTP.start @host, @server.connected_port do |http|
      http.request(req)
    end

    assert_equal "443", res.body
  end

  def test_HEAD_has_no_body
    server_run app: ->(env) { [200, {"Foo" => "Bar"}, ["hello"]] }

    data = send_http_and_read "HEAD / HTTP/1.0\r\n\r\n"

    assert_equal "HTTP/1.0 200 OK\r\nFoo: Bar\r\nContent-Length: 5\r\n\r\n", data
  end

  def test_GET_with_empty_body_has_sane_chunking
    server_run app: ->(env) { [200, {}, [""]] }

    data = send_http_and_read "HEAD / HTTP/1.0\r\n\r\n"

    assert_equal "HTTP/1.0 200 OK\r\nContent-Length: 0\r\n\r\n", data
  end

  def test_early_hints_works
    server_run early_hints: true, app: ->(env) do
     env['rack.early_hints'].call("Link" => "</style.css>; rel=preload; as=style\n</script.js>; rel=preload")
     [200, { "X-Hello" => "World" }, ["Hello world!"]]
    end

    data = send_http_and_read "HEAD / HTTP/1.0\r\n\r\n"

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

  def test_early_hints_are_ignored_if_connection_lost

    def @server.fast_write(*args)
      raise Puma::ConnectionError
    end

    server_run early_hints: true, app: ->(env) do
      env['rack.early_hints'].call("Link" => "</script.js>; rel=preload")
      [200, { "X-Hello" => "World" }, ["Hello world!"]]
    end

    # This request will cause the server to try and send early hints
    _ = send_http "HEAD / HTTP/1.0\r\n\r\n"

    # Give the server some time to try to write (and fail)
    sleep 0.1

    # Expect no errors in stderr
    assert @events.stderr.pos.zero?, "Server didn't swallow the connection error"
  end

  def test_early_hints_is_off_by_default
    server_run app: ->(env) do
     assert_nil env['rack.early_hints']
     [200, { "X-Hello" => "World" }, ["Hello world!"]]
    end

    data = send_http_and_read "HEAD / HTTP/1.0\r\n\r\n"

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
    server_run app: ->(env) { [200, {}, []] }

    data = send_http_and_read "HEAD / HTTP/1.0\r\n\r\n"

    assert_equal "HTTP/1.0 200 OK\r\n\r\n", data
  end

  def test_doesnt_print_backtrace_in_production
    @server.leak_stack_on_error = false
    server_run app: ->(env) { raise "don't leak me bro" }

    data = send_http_and_read "GET / HTTP/1.0\r\n\r\n"

    refute_match(/don't leak me bro/, data)
    assert_match(/HTTP\/1.0 500 Internal Server Error/, data)
  end

  def test_prints_custom_error
    re = lambda { |err| [302, {'Content-Type' => 'text', 'Location' => 'foo.html'}, ['302 found']] }
    @server = Puma::Server.new @app, @events, {:lowlevel_error_handler => re}

    server_run app: ->(env) { raise "don't leak me bro" }

    data = send_http_and_read "GET / HTTP/1.0\r\n\r\n"

    assert_match(/HTTP\/1.0 302 Found/, data)
  end

  def test_leh_gets_env_as_well
    re = lambda { |err,env|
      env['REQUEST_PATH'] || raise('where is env?')
      [302, {'Content-Type' => 'text', 'Location' => 'foo.html'}, ['302 found']]
    }

    @server = Puma::Server.new @app, @events, {:lowlevel_error_handler => re}

    server_run app: ->(env) { raise "don't leak me bro" }

    data = send_http_and_read "GET / HTTP/1.0\r\n\r\n"

    assert_match(/HTTP\/1.0 302 Found/, data)
  end

  def test_custom_http_codes_10
    server_run app: ->(env) { [449, {}, [""]] }

    data = send_http_and_read "GET / HTTP/1.0\r\n\r\n"

    assert_equal "HTTP/1.0 449 CUSTOM\r\nContent-Length: 0\r\n\r\n", data
  end

  def test_custom_http_codes_11
    server_run app: ->(env) { [449, {}, [""]] }

    data = send_http_and_read "GET / HTTP/1.1\r\nConnection: close\r\n\r\n"

    assert_equal "HTTP/1.1 449 CUSTOM\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
  end

  def test_HEAD_returns_content_headers
    server_run app: ->(env) { [200, {"Content-Type" => "application/pdf",
                                     "Content-Length" => "4242"}, []] }

    data = send_http_and_read "HEAD / HTTP/1.0\r\n\r\n"

    assert_equal "HTTP/1.0 200 OK\r\nContent-Type: application/pdf\r\nContent-Length: 4242\r\n\r\n", data
  end

  def test_status_hook_fires_when_server_changes_states

    states = []

    @events.register(:state) { |s| states << s }

    server_run app: ->(env) { [200, {}, [""]] }

    _ = send_http_and_read "HEAD / HTTP/1.0\r\n\r\n"

    assert_equal [:booting, :running], states

    @server.stop(true)

    assert_equal [:booting, :running, :stop, :done], states
  end

  def test_timeout_in_data_phase
    @server.first_data_timeout = 2
    server_run

    sock = send_http "POST / HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\n"

    data = sock.gets

    assert_equal "HTTP/1.1 408 Request Timeout\r\n", data
  end

  def test_http_11_keep_alive_with_body
    server_run app: ->(env) { [200, {"Content-Type" => "plain/text"}, ["hello\n"]] }

    sock = send_http "GET / HTTP/1.1\r\nConnection: Keep-Alive\r\n\r\n"

    h = header sock

    body = sock.gets

    assert_equal ["HTTP/1.1 200 OK", "Content-Type: plain/text", "Content-Length: 6"], h
    assert_equal "hello\n", body

    sock.close
  end

  def test_http_11_close_with_body
    server_run app: ->(env) { [200, {"Content-Type" => "plain/text"}, ["hello"]] }

    data = send_http_and_read "GET / HTTP/1.1\r\nConnection: close\r\n\r\n"

    assert_equal "HTTP/1.1 200 OK\r\nContent-Type: plain/text\r\nConnection: close\r\nContent-Length: 5\r\n\r\nhello", data
  end

  def test_http_11_keep_alive_without_body
    server_run app: ->(env) { [204, {}, []] }

    sock = send_http "GET / HTTP/1.1\r\nConnection: Keep-Alive\r\n\r\n"

    h = header sock

    assert_equal ["HTTP/1.1 204 No Content"], h
  end

  def test_http_11_close_without_body
    server_run app: ->(env) { [204, {}, []] }

    sock = send_http "GET / HTTP/1.1\r\nConnection: close\r\n\r\n"

    h = header sock

    assert_equal ["HTTP/1.1 204 No Content", "Connection: close"], h
  end

  def test_http_10_keep_alive_with_body
    server_run app: ->(env) { [200, {"Content-Type" => "plain/text"}, ["hello\n"]] }

    sock = send_http "GET / HTTP/1.0\r\nConnection: Keep-Alive\r\n\r\n"

    h = header sock

    body = sock.gets

    assert_equal ["HTTP/1.0 200 OK", "Content-Type: plain/text", "Connection: Keep-Alive", "Content-Length: 6"], h
    assert_equal "hello\n", body
  end

  def test_http_10_close_with_body
    server_run app: ->(env) { [200, {"Content-Type" => "plain/text"}, ["hello"]] }

    data = send_http_and_read "GET / HTTP/1.0\r\nConnection: close\r\n\r\n"

    assert_equal "HTTP/1.0 200 OK\r\nContent-Type: plain/text\r\nContent-Length: 5\r\n\r\nhello", data
  end

  def test_http_10_partial_hijack_with_content_length
    body_parts = ['abc', 'de']

    server_run app: ->(env) do
      hijack_lambda = proc do | io |
        io.write(body_parts[0])
        io.write(body_parts[1])
        io.close
      end
      [200, {"Content-Length" => "5", 'rack.hijack' => hijack_lambda}, nil]
    end

    data = send_http_and_read "GET / HTTP/1.0\r\nConnection: close\r\n\r\n"

    assert_equal "HTTP/1.0 200 OK\r\nContent-Length: 5\r\n\r\nabcde", data
  end

  def test_http_10_keep_alive_without_body
    server_run app: ->(env) { [204, {}, []] }

    sock = send_http "GET / HTTP/1.0\r\nConnection: Keep-Alive\r\n\r\n"

    h = header sock

    assert_equal ["HTTP/1.0 204 No Content", "Connection: Keep-Alive"], h
  end

  def test_http_10_close_without_body
    server_run app: ->(env) { [204, {}, []] }

    data = send_http_and_read "GET / HTTP/1.0\r\nConnection: close\r\n\r\n"

    assert_equal "HTTP/1.0 204 No Content\r\n\r\n", data
  end

  def test_Expect_100
    server_run app: ->(env) { [200, {}, [""]] }

    data = send_http_and_read "GET / HTTP/1.1\r\nConnection: close\r\nExpect: 100-continue\r\n\r\n"

    assert_equal "HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
  end

  def test_chunked_request
    body = nil
    server_run app: ->(env) {
      body = env['rack.input'].read
      [200, {}, [""]]
    }

    data = send_http_and_read "GET / HTTP/1.1\r\nConnection: close\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nh\r\n4\r\nello\r\n0\r\n\r\n"

    assert_equal "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
    assert_equal "hello", body
  end

  def test_chunked_request_pause_before_value
    body = nil
    server_run app: ->(env) {
      body = env['rack.input'].read
      [200, {}, [""]]
    }

    sock = send_http "GET / HTTP/1.1\r\nConnection: close\r\nTransfer-Encoding: chunked\r\n\r\n1\r\n"
    sleep 1

    sock << "h\r\n4\r\nello\r\n0\r\n\r\n"

    data = sock.read

    assert_equal "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
    assert_equal "hello", body
  end

  def test_chunked_request_pause_between_chunks
    body = nil
    server_run app: ->(env) {
      body = env['rack.input'].read
      [200, {}, [""]]
    }

    sock = send_http "GET / HTTP/1.1\r\nConnection: close\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nh\r\n"
    sleep 1

    sock << "4\r\nello\r\n0\r\n\r\n"

    data = sock.read

    assert_equal "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
    assert_equal "hello", body
  end

  def test_chunked_request_pause_mid_count
    body = nil
    server_run app: ->(env) {
      body = env['rack.input'].read
      [200, {}, [""]]
    }

    sock = send_http "GET / HTTP/1.1\r\nConnection: close\r\nTransfer-Encoding: chunked\r\n\r\n1\r"
    sleep 1

    sock << "\nh\r\n4\r\nello\r\n0\r\n\r\n"

    data = sock.read

    assert_equal "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
    assert_equal "hello", body
  end

  def test_chunked_request_pause_before_count_newline
    body = nil
    server_run app: ->(env) {
      body = env['rack.input'].read
      [200, {}, [""]]
    }

    sock = send_http "GET / HTTP/1.1\r\nConnection: close\r\nTransfer-Encoding: chunked\r\n\r\n1"
    sleep 1

    sock << "\r\nh\r\n4\r\nello\r\n0\r\n\r\n"

    data = sock.read

    assert_equal "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
    assert_equal "hello", body
  end

  def test_chunked_request_pause_mid_value
    body = nil
    server_run app: ->(env) {
      body = env['rack.input'].read
      [200, {}, [""]]
    }

    sock = send_http "GET / HTTP/1.1\r\nConnection: close\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nh\r\n4\r\ne"
    sleep 1

    sock << "llo\r\n0\r\n\r\n"

    data = sock.read

    assert_equal "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
    assert_equal "hello", body
  end

  def test_chunked_request_pause_between_cr_lf_after_size_of_second_chunk
    body = nil
    server_run app: ->(env)  {
      body = env['rack.input'].read
      [200, {}, [""]]
    }

    part1 = 'a' * 4200

    chunked_body = "#{part1.size.to_s(16)}\r\n#{part1}\r\n1\r\nb\r\n0\r\n\r\n"

    sock = send_http "PUT /path HTTP/1.1\r\nConnection: close\r\nTransfer-Encoding: chunked\r\n\r\n"

    sleep 0.1

    sock << chunked_body[0..-10]

    sleep 0.1

    sock << chunked_body[-9..-1]

    data = sock.read

    assert_equal "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
    assert_equal (part1 + 'b'), body
  end

  def test_chunked_request_pause_between_closing_cr_lf
    body = nil
    server_run app: ->(env) {
      body = env['rack.input'].read
      [200, {}, [""]]
    }

    sock = send_http "PUT /path HTTP/1.1\r\nConnection: close\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r"

    sleep 1

    sock << "\n0\r\n\r\n"

    data = sock.read

    assert_equal "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
    assert_equal 'hello', body
  end

  def test_chunked_request_pause_before_closing_cr_lf
    body = nil
    server_run app: ->(env) {
      body = env['rack.input'].read
      [200, {}, [""]]
    }

    sock = send_http "PUT /path HTTP/1.1\r\nConnection: close\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello"

    sleep 1

    sock << "\r\n0\r\n\r\n"

    data = sock.read

    assert_equal "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
    assert_equal 'hello', body
  end

  def test_chunked_request_header_case
    body = nil
    server_run app: ->(env) {
      body = env['rack.input'].read
      [200, {}, [""]]
    }

    data = send_http_and_read "GET / HTTP/1.1\r\nConnection: close\r\nTransfer-Encoding: Chunked\r\n\r\n1\r\nh\r\n4\r\nello\r\n0\r\n\r\n"

    assert_equal "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
    assert_equal "hello", body
  end

  def test_chunked_keep_alive
    body = nil
    server_run app: ->(env) {
      body = env['rack.input'].read
      [200, {}, [""]]
    }

    sock = send_http "GET / HTTP/1.1\r\nConnection: Keep-Alive\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nh\r\n4\r\nello\r\n0\r\n\r\n"

    h = header sock

    assert_equal ["HTTP/1.1 200 OK", "Content-Length: 0"], h
    assert_equal "hello", body

    sock.close
  end

  def test_chunked_keep_alive_two_back_to_back
    body = nil
    server_run app: ->(env) {
      body = env['rack.input'].read
      [200, {}, [""]]
    }

    sock = send_http "GET / HTTP/1.1\r\nConnection: Keep-Alive\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nh\r\n4\r\nello\r\n0\r\n"

    last_crlf_written = false
    last_crlf_writer = Thread.new do
      sleep 0.1
      sock << "\r"
      sleep 0.1
      sock << "\n"
      last_crlf_written = true
    end

    h = header(sock)
    assert_equal ["HTTP/1.1 200 OK", "Content-Length: 0"], h
    assert_equal "hello", body
    assert_equal true, last_crlf_written

    last_crlf_writer.join

    sock << "GET / HTTP/1.1\r\nConnection: Keep-Alive\r\nTransfer-Encoding: chunked\r\n\r\n4\r\ngood\r\n3\r\nbye\r\n0\r\n\r\n"
    sleep 0.1

    h = header(sock)

    assert_equal ["HTTP/1.1 200 OK", "Content-Length: 0"], h
    assert_equal "goodbye", body

    sock.close
  end

  def test_chunked_keep_alive_two_back_to_back_with_set_remote_address
    body = nil
    remote_addr =nil
    @server = Puma::Server.new @app, @events, { remote_address: :header, remote_address_header: 'HTTP_X_FORWARDED_FOR'}
    server_run app: ->(env) {
      body = env['rack.input'].read
      remote_addr = env['REMOTE_ADDR']
      [200, {}, [""]]
    }

    sock = send_http "GET / HTTP/1.1\r\nX-Forwarded-For: 127.0.0.1\r\nConnection: Keep-Alive\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nh\r\n4\r\nello\r\n0\r\n\r\n"

    h = header sock
    assert_equal ["HTTP/1.1 200 OK", "Content-Length: 0"], h
    assert_equal "hello", body
    assert_equal "127.0.0.1", remote_addr

    sock << "GET / HTTP/1.1\r\nX-Forwarded-For: 127.0.0.2\r\nConnection: Keep-Alive\r\nTransfer-Encoding: chunked\r\n\r\n4\r\ngood\r\n3\r\nbye\r\n0\r\n\r\n"
    sleep 0.1

    h = header(sock)

    assert_equal ["HTTP/1.1 200 OK", "Content-Length: 0"], h
    assert_equal "goodbye", body
    assert_equal "127.0.0.2", remote_addr

    sock.close
  end

  def test_empty_header_values
    server_run app: ->(env) { [200, {"X-Empty-Header" => ""}, []] }

    data = send_http_and_read "HEAD / HTTP/1.0\r\n\r\n"

    assert_equal "HTTP/1.0 200 OK\r\nX-Empty-Header: \r\n\r\n", data
  end

  def test_request_body_wait
    request_body_wait = nil
    server_run app: ->(env) {
      request_body_wait = env['puma.request_body_wait']
      [204, {}, []]
    }

    sock = send_http "POST / HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nh"
    sleep 1
    sock << "ello"

    sock.gets

    # Could be 1000 but the tests get flaky. We don't care if it's extremely precise so much as that
    # it is set to a reasonable number.
    assert_operator request_body_wait, :>=, 900
  end

  def test_request_body_wait_chunked
    request_body_wait = nil
    server_run app: ->(env) {
      request_body_wait = env['puma.request_body_wait']
      [204, {}, []]
    }

    sock = send_http "GET / HTTP/1.1\r\nConnection: close\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nh\r\n"
    sleep 1
    sock << "4\r\nello\r\n0\r\n\r\n"

    sock.gets

    # Could be 1000 but the tests get flaky. We don't care if it's extremely precise so much as that
    # it is set to a reasonable number.
    assert_operator request_body_wait, :>=, 900
  end

  def test_open_connection_wait
    server_run app: ->(_) { [200, {}, ["Hello"]] }
    s = send_http nil
    sleep 0.1
    s << "GET / HTTP/1.0\r\n\r\n"
    assert_equal 'Hello', s.readlines.last
  end

  def test_open_connection_wait_no_queue
    @server = Puma::Server.new @app, @events, queue_requests: false
    test_open_connection_wait
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
