require_relative "helper"
require "puma/events"
require "puma/server"
require "net/http"
require "nio"
require "ipaddr"

class WithoutBacktraceError < StandardError
  def backtrace; nil; end
  def message; "no backtrace error"; end
end

class TestPumaServer < Minitest::Test
  parallelize_me!

  def setup
    @host = "127.0.0.1"

    @ios = []

    @app = ->(env) { [200, {}, [env['rack.url_scheme']]] }

    @log_writer = Puma::LogWriter.strings
    @events = Puma::Events.new
    @server = Puma::Server.new @app, @events, {log_writer: @log_writer}
  end

  def teardown
    @server.stop(true)
    # Errno::EBADF raised on macOS
    @ios.each do |io|
      begin
        io.close if io.respond_to?(:close) && !io.closed?
        File.unlink io.path if io.is_a? File
      rescue Errno::EBADF
      ensure
        io = nil
      end
    end
  end

  def server_run(**options, &block)
    options[:log_writer]  ||= @log_writer
    options[:min_threads] ||= 1
    @server = Puma::Server.new block || @app, @events, options
    @port = (@server.add_tcp_listener @host, 0).addr[1]
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

  # only for shorter bodies!
  def send_http_and_sysread(req)
    send_http(req).sysread 2_048
  end

  def send_http_and_read(req)
    send_http(req).read
  end

  def send_http(req)
    new_connection << req
  end

  def send_proxy_v1_http(req, remote_ip, multisend = false)
    addr = IPAddr.new(remote_ip)
    family = addr.ipv4? ? "TCP4" : "TCP6"
    target = addr.ipv4? ? "127.0.0.1" : "::1"
    conn = new_connection
    if multisend
      conn << "PROXY #{family} #{remote_ip} #{target} 10000 80\r\n"
      sleep 0.15
      conn << req
    else
      conn << ("PROXY #{family} #{remote_ip} #{target} 10000 80\r\n" + req)
    end
  end


  def new_connection
    TCPSocket.new(@host, @port).tap {|sock| @ios << sock}
  end

  def test_normalize_host_header_missing
    server_run do |env|
      [200, {}, [env["SERVER_NAME"], "\n", env["SERVER_PORT"]]]
    end

    data = send_http_and_read "GET / HTTP/1.0\r\n\r\n"
    assert_equal "localhost\n80", data.split("\r\n").last
  end

  def test_normalize_host_header_hostname
    server_run do |env|
      [200, {}, [env["SERVER_NAME"], "\n", env["SERVER_PORT"]]]
    end

    data = send_http_and_read "GET / HTTP/1.0\r\nHost: example.com:456\r\n\r\n"
    assert_equal "example.com\n456", data.split("\r\n").last

    data = send_http_and_read "GET / HTTP/1.0\r\nHost: example.com\r\n\r\n"
    assert_equal "example.com\n80", data.split("\r\n").last
  end

  def test_normalize_host_header_ipv4
    server_run do |env|
      [200, {}, [env["SERVER_NAME"], "\n", env["SERVER_PORT"]]]
    end

    data = send_http_and_read "GET / HTTP/1.0\r\nHost: 123.123.123.123:456\r\n\r\n"
    assert_equal "123.123.123.123\n456", data.split("\r\n").last

    data = send_http_and_read "GET / HTTP/1.0\r\nHost: 123.123.123.123\r\n\r\n"
    assert_equal "123.123.123.123\n80", data.split("\r\n").last
  end

  def test_normalize_host_header_ipv6
    server_run do |env|
      [200, {}, [env["SERVER_NAME"], "\n", env["SERVER_PORT"]]]
    end

    data = send_http_and_read "GET / HTTP/1.0\r\nHost: [::ffff:127.0.0.1]:9292\r\n\r\n"
    assert_equal "[::ffff:127.0.0.1]\n9292", data.split("\r\n").last

    data = send_http_and_read "GET / HTTP/1.0\r\nHost: [::1]:9292\r\n\r\n"
    assert_equal "[::1]\n9292", data.split("\r\n").last

    data = send_http_and_read "GET / HTTP/1.0\r\nHost: [::1]\r\n\r\n"
    assert_equal "[::1]\n80", data.split("\r\n").last
  end

  def test_streaming_body
    server_run do |env|
      body = lambda do |stream|
        stream.write("Hello World")
        stream.close
      end

      [200, {}, body]
    end

    data = send_http_and_read "GET / HTTP/1.0\r\nConnection: close\r\n\r\n"

    assert_equal "Hello World", data.split("\r\n\r\n", 2).last
  end

  def test_file_body
    random_bytes = SecureRandom.random_bytes(4096 * 32)

    tf = tempfile_create("test_file_body", random_bytes)

    server_run { |env| [200, {}, tf] }

    data = +''
    skt = send_http("GET / HTTP/1.1\r\nHost: [::ffff:127.0.0.1]:#{@port}\r\n\r\n")
    data << skt.sysread(65_536) while skt.wait_readable(0.1)

    ary = data.split("\r\n\r\n", 2)

    assert_equal random_bytes.bytesize, ary.last.bytesize
    assert_equal random_bytes, ary.last
  ensure
    tf.close
  end

  def test_file_to_path
    random_bytes = SecureRandom.random_bytes(4096 * 32)

    tf = tempfile_create("test_file_to_path", random_bytes)
    path = tf.path

    obj = Object.new
    obj.singleton_class.send(:define_method, :to_path) { path }
    obj.singleton_class.send(:define_method, :each) { path } # dummy, method needs to exist

    server_run { |env| [200, {}, obj] }

    data = +''
    skt = send_http("GET / HTTP/1.1\r\nHost: [::ffff:127.0.0.1]:#{@port}\r\n\r\n")
    data << skt.sysread(65_536) while skt.wait_readable(0.1)
    ary = data.split("\r\n\r\n", 2)

    assert_equal random_bytes.bytesize, ary.last.bytesize
    assert_equal random_bytes, ary.last
  ensure
    tf.close
  end

  def test_proper_stringio_body
    data = nil

    server_run do |env|
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
    server_run do |env|
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

    server_run do
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
    server_run do |env|
      [200, {}, [env['SERVER_PORT']]]
    end

    req = Net::HTTP::Get.new '/'
    req['HOST'] = 'example.com'

    res = Net::HTTP.start @host, @port do |http|
      http.request(req)
    end

    assert_equal "80", res.body
  end

  def test_default_server_port_respects_x_forwarded_proto
    server_run do |env|
      [200, {}, [env['SERVER_PORT']]]
    end

    req = Net::HTTP::Get.new("/")
    req['HOST'] = "example.com"
    req['X-FORWARDED-PROTO'] = "https,http"

    res = Net::HTTP.start @host, @port do |http|
      http.request(req)
    end

    assert_equal "443", res.body
  end

  def test_HEAD_has_no_body
    server_run { [200, {"Foo" => "Bar"}, ["hello"]] }

    data = send_http_and_read "HEAD / HTTP/1.0\r\n\r\n"

    assert_equal "HTTP/1.0 200 OK\r\nFoo: Bar\r\nContent-Length: 5\r\n\r\n", data
  end

  def test_GET_with_empty_body_has_sane_chunking
    server_run { [200, {}, [""]] }

    data = send_http_and_read "HEAD / HTTP/1.0\r\n\r\n"

    assert_equal "HTTP/1.0 200 OK\r\nContent-Length: 0\r\n\r\n", data
  end

  def test_early_hints_works
    server_run(early_hints: true) do |env|
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

    server_run(early_hints: true) do |env|
      env['rack.early_hints'].call("Link" => "</script.js>; rel=preload")
      [200, { "X-Hello" => "World" }, ["Hello world!"]]
    end

    def @server.fast_write(*args)
      raise Puma::ConnectionError
    end

    # This request will cause the server to try and send early hints
    _ = send_http "HEAD / HTTP/1.0\r\n\r\n"

    # Give the server some time to try to write (and fail)
    sleep 0.1

    # Expect no errors in stderr
    assert @log_writer.stderr.pos.zero?, "Server didn't swallow the connection error"
  end

  def test_early_hints_is_off_by_default
    server_run do |env|
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

  def test_request_payload_too_large
    server_run(http_content_length_limit: 10)

    sock = send_http "POST / HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\nContent-Length: 19\r\n\r\n"
    sock << "hello world foo bar"

    data = sock.gets

    assert_equal "HTTP/1.1 413 Payload Too Large\r\n", data
  end

  def test_http_11_keep_alive_with_large_payload
    server_run(http_content_length_limit: 10) { [204, {}, []] }

    sock = send_http "GET / HTTP/1.1\r\nConnection: Keep-Alive\r\nContent-Length: 17\r\n\r\n"
    sock << "hello world foo bar"
    h = header sock

    assert_equal ["HTTP/1.1 413 Payload Too Large", "Content-Length: 17"], h

  end

  def test_GET_with_no_body_has_sane_chunking
    server_run { [200, {}, []] }

    data = send_http_and_read "HEAD / HTTP/1.0\r\n\r\n"

    assert_equal "HTTP/1.0 200 OK\r\nContent-Length: 0\r\n\r\n", data
  end

  def test_doesnt_print_backtrace_in_production
    server_run(environment: :production) { raise "don't leak me bro" }

    data = send_http_and_read "GET / HTTP/1.0\r\n\r\n"

    refute_match(/don't leak me bro/, data)
    assert_match(/HTTP\/1.0 500 Internal Server Error/, data)
  end

  def test_eof_on_connection_close_is_not_logged_as_an_error
    server_run

    new_connection.close # Make a connection and close without writing

    @server.stop(true)
    stderr = @log_writer.stderr.string
    assert stderr.empty?, "Expected stderr from server to be empty but it was #{stderr.inspect}"
  end

  def test_force_shutdown_custom_error_message
    handler = lambda {|err, env, status| [500, {"Content-Type" => "application/json"}, ["{}\n"]]}
    server_run(lowlevel_error_handler: handler, force_shutdown_after: 2) do
      @server.stop
      sleep 5
    end

    data = send_http_and_read "GET / HTTP/1.0\r\n\r\n"

    assert_match(/HTTP\/1.0 500 Internal Server Error/, data)
    assert_match(/Content-Type: application\/json/, data)
    assert_match(/{}\n$/, data)
  end

  class ArrayClose < Array
    attr_reader :is_closed
    def closed?
      @is_closed
    end

    def close
      @is_closed = true
    end
  end

  # returns status as an array, which throws lowlevel error
  def test_lowlevel_error_body_close
    app_body = ArrayClose.new(['lowlevel_error'])

    server_run(log_writer: @log_writer, :force_shutdown_after => 2) do
      [[0,1], {}, app_body]
    end

    data = send_http_and_sysread "GET / HTTP/1.0\r\n\r\n"

    assert_includes data, 'HTTP/1.0 500 Internal Server Error'
    assert_includes data, "Puma caught this error: undefined method `to_i' for"
    assert_includes data, "Array"
    refute_includes data, 'lowlevel_error'
    sleep 0.1 unless ::Puma::IS_MRI
    assert app_body.closed?
  end

  def test_lowlevel_error_message
    server_run(log_writer: @log_writer, :force_shutdown_after => 2) do
      raise NoMethodError, "Oh no an error"
    end

    data = send_http_and_sysread "GET / HTTP/1.0\r\n\r\n"

    assert_includes data, 'HTTP/1.0 500 Internal Server Error'
    assert_match(/Puma caught this error: Oh no an error.*\(NoMethodError\).*test\/test_puma_server.rb/m, data)
  end

  def test_lowlevel_error_message_without_backtrace
    server_run(log_writer: @log_writer, :force_shutdown_after => 2) do
      raise WithoutBacktraceError.new
    end

    data = send_http_and_sysread "GET / HTTP/1.1\r\n\r\n"
    assert_includes data, 'HTTP/1.1 500 Internal Server Error'
    assert_includes data, 'Puma caught this error: no backtrace error (WithoutBacktraceError)'
    assert_includes data, '<no backtrace available>'
  end

  def test_force_shutdown_error_default
    server_run(force_shutdown_after: 2) do
      @server.stop
      sleep 5
    end

    data = send_http_and_read "GET / HTTP/1.0\r\n\r\n"

    assert_match(/HTTP\/1.0 503 Service Unavailable/, data)
    assert_match(/Puma caught this error.+Puma::ThreadPool::ForceShutdown/, data)
  end

  def test_prints_custom_error
    re = lambda { |err| [302, {'Content-Type' => 'text', 'Location' => 'foo.html'}, ['302 found']] }
    server_run(lowlevel_error_handler: re) { raise "don't leak me bro" }

    data = send_http_and_read "GET / HTTP/1.0\r\n\r\n"

    assert_match(/HTTP\/1.0 302 Found/, data)
  end

  def test_leh_gets_env_as_well
    re = lambda { |err,env|
      env['REQUEST_PATH'] || raise('where is env?')
      [302, {'Content-Type' => 'text', 'Location' => 'foo.html'}, ['302 found']]
    }

    server_run(lowlevel_error_handler: re) { raise "don't leak me bro" }

    data = send_http_and_read "GET / HTTP/1.0\r\n\r\n"

    assert_match(/HTTP\/1.0 302 Found/, data)
  end

  def test_leh_has_status
    re = lambda { |err, env, status|
      raise "Cannot find status" unless status
      [302, {'Content-Type' => 'text', 'Location' => 'foo.html'}, ['302 found']]
    }

    server_run(lowlevel_error_handler: re) { raise "don't leak me bro" }

    data = send_http_and_read "GET / HTTP/1.0\r\n\r\n"

    assert_match(/HTTP\/1.0 302 Found/, data)
  end

  def test_custom_http_codes_10
    server_run { [449, {}, [""]] }

    data = send_http_and_read "GET / HTTP/1.0\r\n\r\n"

    assert_equal "HTTP/1.0 449 CUSTOM\r\nContent-Length: 0\r\n\r\n", data
  end

  def test_custom_http_codes_11
    server_run { [449, {}, [""]] }

    data = send_http_and_read "GET / HTTP/1.1\r\nConnection: close\r\n\r\n"

    assert_equal "HTTP/1.1 449 CUSTOM\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
  end

  def test_HEAD_returns_content_headers
    server_run { [200, {"Content-Type" => "application/pdf",
                                     "Content-Length" => "4242"}, []] }

    data = send_http_and_read "HEAD / HTTP/1.0\r\n\r\n"

    assert_equal "HTTP/1.0 200 OK\r\nContent-Type: application/pdf\r\nContent-Length: 4242\r\n\r\n", data
  end

  def test_status_hook_fires_when_server_changes_states

    states = []

    @events.register(:state) { |s| states << s }

    server_run { [200, {}, [""]] }

    _ = send_http_and_read "HEAD / HTTP/1.0\r\n\r\n"

    assert_equal [:booting, :running], states

    @server.stop(true)

    assert_equal [:booting, :running, :stop, :done], states
  end

  def test_timeout_in_data_phase(**options)
    server_run(first_data_timeout: 1, **options)

    sock = send_http "POST / HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\n"

    sock << "Hello" unless sock.wait_readable(1.15)

    data = sock.gets

    assert_equal "HTTP/1.1 408 Request Timeout\r\n", data
  end

  def test_timeout_data_no_queue
    test_timeout_in_data_phase(queue_requests: false)
  end

  # https://github.com/puma/puma/issues/2574
  def test_no_timeout_after_data_received
    @server.instance_variable_set(:@first_data_timeout, 1)
    server_run

    sock = send_http "POST / HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\nContent-Length: 11\r\n\r\n"
    sleep 0.5

    sock << "hello"
    sleep 0.5
    sock << "world"
    sleep 0.5
    sock << "!"

    data = sock.gets

    assert_equal "HTTP/1.1 200 OK\r\n", data
  end

  def test_no_timeout_after_data_received_no_queue
    @server = Puma::Server.new @app, @events, {log_writer: @log_writer, queue_requests: false}
    test_no_timeout_after_data_received
  end

  def test_http_11_keep_alive_with_body
    server_run { [200, {"Content-Type" => "plain/text"}, ["hello\n"]] }

    sock = send_http "GET / HTTP/1.1\r\nConnection: Keep-Alive\r\n\r\n"

    h = header sock

    body = sock.gets

    assert_equal ["HTTP/1.1 200 OK", "Content-Type: plain/text", "Content-Length: 6"], h
    assert_equal "hello\n", body

    sock.close
  end

  def test_http_11_close_with_body
    server_run { [200, {"Content-Type" => "plain/text"}, ["hello"]] }

    data = send_http_and_read "GET / HTTP/1.1\r\nConnection: close\r\n\r\n"

    assert_equal "HTTP/1.1 200 OK\r\nContent-Type: plain/text\r\nConnection: close\r\nContent-Length: 5\r\n\r\nhello", data
  end

  def test_http_11_keep_alive_without_body
    server_run { [204, {}, []] }

    sock = send_http "GET / HTTP/1.1\r\nConnection: Keep-Alive\r\n\r\n"

    h = header sock

    assert_equal ["HTTP/1.1 204 No Content"], h
  end

  def test_http_11_close_without_body
    server_run { [204, {}, []] }

    sock = send_http "GET / HTTP/1.1\r\nConnection: close\r\n\r\n"

    h = header sock

    assert_equal ["HTTP/1.1 204 No Content", "Connection: close"], h
  end

  def test_http_10_keep_alive_with_body
    server_run { [200, {"Content-Type" => "plain/text"}, ["hello\n"]] }

    sock = send_http "GET / HTTP/1.0\r\nConnection: Keep-Alive\r\n\r\n"

    h = header sock

    body = sock.gets

    assert_equal ["HTTP/1.0 200 OK", "Content-Type: plain/text", "Connection: Keep-Alive", "Content-Length: 6"], h
    assert_equal "hello\n", body
  end

  def test_http_10_close_with_body
    server_run { [200, {"Content-Type" => "plain/text"}, ["hello"]] }

    data = send_http_and_read "GET / HTTP/1.0\r\nConnection: close\r\n\r\n"

    assert_equal "HTTP/1.0 200 OK\r\nContent-Type: plain/text\r\nContent-Length: 5\r\n\r\nhello", data
  end

  def test_http_10_keep_alive_without_body
    server_run { [204, {}, []] }

    sock = send_http "GET / HTTP/1.0\r\nConnection: Keep-Alive\r\n\r\n"

    h = header sock

    assert_equal ["HTTP/1.0 204 No Content", "Connection: Keep-Alive"], h
  end

  def test_http_10_close_without_body
    server_run { [204, {}, []] }

    data = send_http_and_read "GET / HTTP/1.0\r\nConnection: close\r\n\r\n"

    assert_equal "HTTP/1.0 204 No Content\r\n\r\n", data
  end

  def test_Expect_100
    server_run { [200, {}, [""]] }

    data = send_http_and_read "GET / HTTP/1.1\r\nConnection: close\r\nExpect: 100-continue\r\n\r\n"

    assert_equal "HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
  end

  def test_chunked_request
    body = nil
    content_length = nil
    transfer_encoding = nil
    server_run { |env|
      body = env['rack.input'].read
      content_length = env['CONTENT_LENGTH']
      transfer_encoding = env['HTTP_TRANSFER_ENCODING']
      [200, {}, [""]]
    }

    data = send_http_and_read "GET / HTTP/1.1\r\nConnection: close\r\nTransfer-Encoding: gzip,chunked\r\n\r\n1\r\nh\r\n4\r\nello\r\n0\r\n\r\n"

    assert_equal "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
    assert_equal "hello", body
    assert_equal "5", content_length
    assert_nil transfer_encoding
  end

  def test_large_chunked_request
    body = nil
    content_length = nil
    server_run { |env|
      body = env['rack.input'].read
      content_length = env['CONTENT_LENGTH']
      [200, {}, [""]]
    }

    header = "GET / HTTP/1.1\r\nConnection: close\r\nTransfer-Encoding: chunked\r\n\r\n"

    chunk_header_size = 6 # 4fb8\r\n
    # Current implementation reads one chunk of CHUNK_SIZE, then more chunks of size 4096.
    # We want a chunk to split exactly after "#{request_body}\r", before the "\n".
    edge_case_size = Puma::Const::CHUNK_SIZE + 4096 - header.size - chunk_header_size - 1

    margin = 0 # 0 for only testing this specific case, increase to test more surrounding sizes
    (-margin..margin).each do |i|
      size = edge_case_size + i
      request_body = '.' * size
      request = "#{header}#{size.to_s(16)}\r\n#{request_body}\r\n0\r\n\r\n"

      data = send_http_and_read request

      assert_equal "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
      assert_equal size, Integer(content_length)
      assert_equal request_body, body
    end
  end

  def test_chunked_request_pause_before_value
    body = nil
    content_length = nil
    server_run { |env|
      body = env['rack.input'].read
      content_length = env['CONTENT_LENGTH']
      [200, {}, [""]]
    }

    sock = send_http "GET / HTTP/1.1\r\nConnection: close\r\nTransfer-Encoding: chunked\r\n\r\n1\r\n"
    sleep 1

    sock << "h\r\n4\r\nello\r\n0\r\n\r\n"

    data = sock.read

    assert_equal "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
    assert_equal "hello", body
    assert_equal "5", content_length
  end

  def test_chunked_request_pause_between_chunks
    body = nil
    content_length = nil
    server_run { |env|
      body = env['rack.input'].read
      content_length = env['CONTENT_LENGTH']
      [200, {}, [""]]
    }

    sock = send_http "GET / HTTP/1.1\r\nConnection: close\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nh\r\n"
    sleep 1

    sock << "4\r\nello\r\n0\r\n\r\n"

    data = sock.read

    assert_equal "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
    assert_equal "hello", body
    assert_equal "5", content_length
  end

  def test_chunked_request_pause_mid_count
    body = nil
    content_length = nil
    server_run { |env|
      body = env['rack.input'].read
      content_length = env['CONTENT_LENGTH']
      [200, {}, [""]]
    }

    sock = send_http "GET / HTTP/1.1\r\nConnection: close\r\nTransfer-Encoding: chunked\r\n\r\n1\r"
    sleep 1

    sock << "\nh\r\n4\r\nello\r\n0\r\n\r\n"

    data = sock.read

    assert_equal "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
    assert_equal "hello", body
    assert_equal "5", content_length
  end

  def test_chunked_request_pause_before_count_newline
    body = nil
    content_length = nil
    server_run { |env|
      body = env['rack.input'].read
      content_length = env['CONTENT_LENGTH']
      [200, {}, [""]]
    }

    sock = send_http "GET / HTTP/1.1\r\nConnection: close\r\nTransfer-Encoding: chunked\r\n\r\n1"
    sleep 1

    sock << "\r\nh\r\n4\r\nello\r\n0\r\n\r\n"

    data = sock.read

    assert_equal "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
    assert_equal "hello", body
    assert_equal "5", content_length
  end

  def test_chunked_request_pause_mid_value
    body = nil
    content_length = nil
    server_run { |env|
      body = env['rack.input'].read
      content_length = env['CONTENT_LENGTH']
      [200, {}, [""]]
    }

    sock = send_http "GET / HTTP/1.1\r\nConnection: close\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nh\r\n4\r\ne"
    sleep 1

    sock << "llo\r\n0\r\n\r\n"

    data = sock.read

    assert_equal "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
    assert_equal "hello", body
    assert_equal "5", content_length
  end

  def test_chunked_request_pause_between_cr_lf_after_size_of_second_chunk
    body = nil
    content_length = nil
    server_run { |env|
      body = env['rack.input'].read
      content_length = env['CONTENT_LENGTH']
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
    assert_equal "4201", content_length
  end

  def test_chunked_request_pause_between_closing_cr_lf
    body = nil
    content_length = nil
    server_run { |env|
      body = env['rack.input'].read
      content_length = env['CONTENT_LENGTH']
      [200, {}, [""]]
    }

    sock = send_http "PUT /path HTTP/1.1\r\nConnection: close\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r"

    sleep 1

    sock << "\n0\r\n\r\n"

    data = sock.read

    assert_equal "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
    assert_equal 'hello', body
    assert_equal "5", content_length
  end

  def test_chunked_request_pause_before_closing_cr_lf
    body = nil
    content_length = nil
    server_run { |env|
      body = env['rack.input'].read
      content_length = env['CONTENT_LENGTH']
      [200, {}, [""]]
    }

    sock = send_http "PUT /path HTTP/1.1\r\nConnection: close\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello"

    sleep 1

    sock << "\r\n0\r\n\r\n"

    data = sock.read

    assert_equal "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
    assert_equal 'hello', body
    assert_equal "5", content_length
  end

  def test_chunked_request_header_case
    body = nil
    content_length = nil
    server_run { |env|
      body = env['rack.input'].read
      content_length = env['CONTENT_LENGTH']
      [200, {}, [""]]
    }

    data = send_http_and_read "GET / HTTP/1.1\r\nConnection: close\r\nTransfer-Encoding: Chunked\r\n\r\n1\r\nh\r\n4\r\nello\r\n0\r\n\r\n"

    assert_equal "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", data
    assert_equal "hello", body
    assert_equal "5", content_length
  end

  def test_chunked_keep_alive
    body = nil
    content_length = nil
    server_run { |env|
      body = env['rack.input'].read
      content_length = env['CONTENT_LENGTH']
      [200, {}, [""]]
    }

    sock = send_http "GET / HTTP/1.1\r\nConnection: Keep-Alive\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nh\r\n4\r\nello\r\n0\r\n\r\n"

    h = header sock

    assert_equal ["HTTP/1.1 200 OK", "Content-Length: 0"], h
    assert_equal "hello", body
    assert_equal "5", content_length

    sock.close
  end

  def test_chunked_keep_alive_two_back_to_back
    body = nil
    content_length = nil
    server_run { |env|
      body = env['rack.input'].read
      content_length = env['CONTENT_LENGTH']
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
    assert_equal "5", content_length
    sleep 0.05 if TRUFFLE
    assert_equal true, last_crlf_written

    last_crlf_writer.join

    sock << "GET / HTTP/1.1\r\nConnection: Keep-Alive\r\nTransfer-Encoding: chunked\r\n\r\n4\r\ngood\r\n3\r\nbye\r\n0\r\n\r\n"
    sleep 0.1

    h = header(sock)

    assert_equal ["HTTP/1.1 200 OK", "Content-Length: 0"], h
    assert_equal "goodbye", body
    assert_equal "7", content_length

    sock.close
  end

  def test_chunked_keep_alive_two_back_to_back_with_set_remote_address
    body = nil
    content_length = nil
    remote_addr =nil
    server_run(remote_address: :header, remote_address_header: 'HTTP_X_FORWARDED_FOR') { |env|
      body = env['rack.input'].read
      content_length = env['CONTENT_LENGTH']
      remote_addr = env['REMOTE_ADDR']
      [200, {}, [""]]
    }

    sock = send_http "GET / HTTP/1.1\r\nX-Forwarded-For: 127.0.0.1\r\nConnection: Keep-Alive\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nh\r\n4\r\nello\r\n0\r\n\r\n"

    h = header sock
    assert_equal ["HTTP/1.1 200 OK", "Content-Length: 0"], h
    assert_equal "hello", body
    assert_equal "5", content_length
    assert_equal "127.0.0.1", remote_addr

    sock << "GET / HTTP/1.1\r\nX-Forwarded-For: 127.0.0.2\r\nConnection: Keep-Alive\r\nTransfer-Encoding: chunked\r\n\r\n4\r\ngood\r\n3\r\nbye\r\n0\r\n\r\n"
    sleep 0.1

    h = header(sock)

    assert_equal ["HTTP/1.1 200 OK", "Content-Length: 0"], h
    assert_equal "goodbye", body
    assert_equal "7", content_length
    assert_equal "127.0.0.2", remote_addr

    sock.close
  end

  def test_chunked_encoding
    enc = Encoding::UTF_16LE
    str = "──иї_テスト──\n".encode enc

    server_run {
      hdrs = {}
      hdrs['Content-Type'] = "text; charset=#{enc.to_s.downcase}"

      body = Enumerator.new do |yielder|
        100.times do |entry|
          yielder << str
        end
        yielder << "\nHello World\n".encode(enc)
      end

      [200, hdrs, body]
    }

    body = Net::HTTP.start @host, @port do |http|
      http.request(Net::HTTP::Get.new '/').body.force_encoding(enc)
    end
    assert_includes body, str
    assert_equal enc, body.encoding
  end

  def test_empty_header_values
    server_run { [200, {"X-Empty-Header" => ""}, []] }

    data = send_http_and_read "HEAD / HTTP/1.0\r\n\r\n"

    assert_equal "HTTP/1.0 200 OK\r\nX-Empty-Header: \r\nContent-Length: 0\r\n\r\n", data
  end

  def test_request_body_wait
    request_body_wait = nil
    server_run { |env|
      request_body_wait = env['puma.request_body_wait']
      [204, {}, []]
    }

    sock = send_http "POST / HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nh"
    sleep 1
    sock << "ello"

    sock.gets

    assert request_body_wait.is_a?(Float)
    # Could be 1000 but the tests get flaky. We don't care if it's extremely precise so much as that
    # it is set to a reasonable number.
    assert_operator request_body_wait, :>=, 900
  end

  def test_request_body_wait_chunked
    request_body_wait = nil
    server_run { |env|
      request_body_wait = env['puma.request_body_wait']
      [204, {}, []]
    }

    sock = send_http "GET / HTTP/1.1\r\nConnection: close\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nh\r\n"
    sleep 3
    sock << "4\r\nello\r\n0\r\n\r\n"

    sock.gets

    # Could be 1000 but the tests get flaky. We don't care if it's extremely precise so much as that
    # it is set to a reasonable number.
    assert_operator request_body_wait, :>=, 900
  end

  def test_open_connection_wait(**options)
    server_run(**options) { [200, {}, ["Hello"]] }
    s = send_http nil
    sleep 0.1
    s << "GET / HTTP/1.0\r\n\r\n"
    assert_equal 'Hello', s.readlines.last
  end

  def test_open_connection_wait_no_queue
    test_open_connection_wait(queue_requests: false)
  end

  # Rack may pass a newline in a header expecting us to split it.
  def test_newline_splits
    server_run { [200, {'X-header' => "first line\nsecond line"}, ["Hello"]] }

    data = send_http_and_read "HEAD / HTTP/1.0\r\n\r\n"

    assert_match "X-header: first line\r\nX-header: second line\r\n", data
  end

  def test_newline_splits_in_early_hint
    server_run(early_hints: true) do |env|
      env['rack.early_hints'].call({'X-header' => "first line\nsecond line"})
      [200, {}, ["Hello world!"]]
    end

    data = send_http_and_read "HEAD / HTTP/1.0\r\n\r\n"

    assert_match "X-header: first line\r\nX-header: second line\r\n", data
  end

  def test_proxy_protocol
    server_run(remote_address: :proxy_protocol, remote_address_proxy_protocol: :v1) do |env|
      [200, {}, [env["REMOTE_ADDR"]]]
    end

    remote_addr = send_proxy_v1_http("GET / HTTP/1.0\r\n\r\n", "1.2.3.4").read.split("\r\n").last
    assert_equal '1.2.3.4', remote_addr

    remote_addr = send_proxy_v1_http("GET / HTTP/1.0\r\n\r\n", "fd00::1").read.split("\r\n").last
    assert_equal 'fd00::1', remote_addr

    remote_addr = send_proxy_v1_http("GET / HTTP/1.0\r\n\r\n", "fd00::1", true).read.split("\r\n").last
    assert_equal 'fd00::1', remote_addr
  end

  # To comply with the Rack spec, we have to split header field values
  # containing newlines into multiple headers.
  def assert_does_not_allow_http_injection(app, opts = {})
    server_run(early_hints: opts[:early_hints], &app)

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

  # Perform a server shutdown while requests are pending (one in app-server response, one still sending client request).
  def shutdown_requests(s1_complete: true, s1_response: nil, post: false, s2_response: nil, **options)
    mutex = Mutex.new
    app_finished = ConditionVariable.new
    server_run(**options) { |env|
      path = env['REQUEST_PATH']
      mutex.synchronize do
        app_finished.signal
        app_finished.wait(mutex) if path == '/s1'
      end
      [204, {}, []]
    }

    pool = @server.instance_variable_get(:@thread_pool)

    # Trigger potential race condition by pausing Reactor#add until shutdown begins.
    if options.fetch(:queue_requests, true)
      reactor = @server.instance_variable_get(:@reactor)
      reactor.instance_variable_set(:@pool, pool)
      reactor.extend(Module.new do
        def add(client)
          if client.env['REQUEST_PATH'] == '/s2'
            Thread.pass until @pool.instance_variable_get(:@shutdown)
          end
          super
        end
      end)
    end

    s1 = nil
    s2 = send_http post ?
      "POST /s2 HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nhi!" :
      "GET /s2 HTTP/1.1\r\n"
    mutex.synchronize do
      s1 = send_http "GET /s1 HTTP/1.1\r\n\r\n"
      app_finished.wait(mutex)
      app_finished.signal if s1_complete
    end
    @server.stop
    Thread.pass until pool.instance_variable_get(:@shutdown)

    assert_match(s1_response, s1.gets) if s1_response

    # Send s2 after shutdown begins
    s2 << "\r\n" unless s2.wait_readable(0.2)

    assert s2.wait_readable(10), 'timeout waiting for response'
    s2_result = begin
      s2.gets
    rescue Errno::ECONNABORTED, Errno::ECONNRESET
      # Some platforms raise errors instead of returning a response/EOF when a TCP connection is aborted.
      post ? '408' : nil
    end

    if s2_response
      assert_match s2_response, s2_result
    else
      assert_nil s2_result
    end
  end

  # Shutdown should allow pending requests and app-responses to complete.
  def test_shutdown_requests
    opts = {s1_response: /204/, s2_response: /204/}
    shutdown_requests(**opts)
    shutdown_requests(**opts, queue_requests: false)
  end

  # Requests still pending after `force_shutdown_after` should have connection closed (408 w/pending POST body).
  # App-responses still pending should return 503 (uncaught Puma::ThreadPool::ForceShutdown exception).
  def test_force_shutdown
    opts = {s1_complete: false, s1_response: /503/, s2_response: nil, force_shutdown_after: 0}
    shutdown_requests(**opts)
    shutdown_requests(**opts, queue_requests: false)
    shutdown_requests(**opts, post: true, s2_response: /408/)
  end

  def test_http11_connection_header_queue
    server_run { [200, {}, [""]] }

    sock = send_http "GET / HTTP/1.1\r\n\r\n"
    assert_equal ["HTTP/1.1 200 OK", "Content-Length: 0"], header(sock)

    sock << "GET / HTTP/1.1\r\nConnection: close\r\n\r\n"
    assert_equal ["HTTP/1.1 200 OK", "Connection: close", "Content-Length: 0"], header(sock)

    sock.close
  end

  def test_http10_connection_header_queue
    server_run { [200, {}, [""]] }

    sock = send_http "GET / HTTP/1.0\r\nConnection: keep-alive\r\n\r\n"
    assert_equal ["HTTP/1.0 200 OK", "Connection: Keep-Alive", "Content-Length: 0"], header(sock)

    sock << "GET / HTTP/1.0\r\n\r\n"
    assert_equal ["HTTP/1.0 200 OK", "Content-Length: 0"], header(sock)
    sock.close
  end

  def test_http11_connection_header_no_queue
    server_run(queue_requests: false) { [200, {}, [""]] }
    sock = send_http "GET / HTTP/1.1\r\n\r\n"
    assert_equal ["HTTP/1.1 200 OK", "Connection: close", "Content-Length: 0"], header(sock)
    sock.close
  end

  def test_http10_connection_header_no_queue
    server_run(queue_requests: false) { [200, {}, [""]] }
    sock = send_http "GET / HTTP/1.0\r\n\r\n"
    assert_equal ["HTTP/1.0 200 OK", "Content-Length: 0"], header(sock)
    sock.close
  end

  def stub_accept_nonblock(error)
    @port = (@server.add_tcp_listener @host, 0).addr[1]
    io = @server.binder.ios.last

    accept_old = io.method(:accept_nonblock)
    io.singleton_class.send :define_method, :accept_nonblock do
      accept_old.call.close
      raise error
    end

    @server.run
    new_connection
    sleep 0.01
  end

  # System-resource errors such as EMFILE should not be silently swallowed by accept loop.
  def test_accept_emfile
    stub_accept_nonblock Errno::EMFILE.new('accept(2)')
    refute_empty @log_writer.stderr.string, "Expected EMFILE error not logged"
  end

  # Retryable errors such as ECONNABORTED should be silently swallowed by accept loop.
  def test_accept_econnaborted
    # Match Ruby #accept_nonblock implementation, ECONNABORTED error is extended by IO::WaitReadable.
    error = Errno::ECONNABORTED.new('accept(2) would block').tap {|e| e.extend IO::WaitReadable}
    stub_accept_nonblock(error)
    assert_empty @log_writer.stderr.string
  end

  # see      https://github.com/puma/puma/issues/2390
  # fixed by https://github.com/puma/puma/pull/2279
  #
  def test_client_quick_close_no_lowlevel_error_handler_call
    handler = ->(err, env, status) {
      @log_writer.stdout.write "LLEH #{err.message}"
      [500, {"Content-Type" => "application/json"}, ["{}\n"]]
    }

    server_run(lowlevel_error_handler: handler) { [200, {}, ['Hello World']] }

    # valid req & read, close
    sock = TCPSocket.new @host, @port
    sock.syswrite "GET / HTTP/1.0\r\n\r\n"
    sleep 0.05  # macOS TruffleRuby may not get the body without
    resp = sock.sysread 256
    sock.close
    assert_match 'Hello World', resp
    sleep 0.5
    assert_empty @log_writer.stdout.string

    # valid req, close
    sock = TCPSocket.new @host, @port
    sock.syswrite "GET / HTTP/1.0\r\n\r\n"
    sock.close
    sleep 0.5
    assert_empty @log_writer.stdout.string

    # invalid req, close
    sock = TCPSocket.new @host, @port
    sock.syswrite "GET / HTTP"
    sock.close
    sleep 0.5
    assert_empty @log_writer.stdout.string
  end

  def test_idle_connections_closed_immediately_on_shutdown
    server_run
    sock = new_connection
    sleep 0.5 # give enough time for new connection to enter reactor
    @server.stop false

    assert sock.wait_readable(1), 'Unexpected timeout'
    assert_raises EOFError do
      sock.read_nonblock(256)
    end
  end

  def test_run_stop_thread_safety
    100.times do
      thread = @server.run
      @server.stop
      assert thread.join(1)
    end
  end

  def test_command_ignored_before_run
    @server.stop # ignored
    @server.run
    @server.halt
    done = Queue.new
    @server.events.register(:state) do |state|
      done << @server.instance_variable_get(:@status) if state == :done
    end
    assert_equal :halt, done.pop
  end

  def test_custom_io_selector
    backend = NIO::Selector.backends.first

    @server = Puma::Server.new @app, @events, {log_writer: @log_writer, :io_selector_backend => backend}
    @server.run

    selector = @server.instance_variable_get(:@reactor).instance_variable_get(:@selector)

    assert_equal selector.backend, backend
  end

  def test_drain_on_shutdown(drain=true)
    num_connections = 10

    wait = Queue.new
    server_run(drain_on_shutdown: drain, max_threads: 1) do
      wait.pop
      [200, {}, ["DONE"]]
    end
    connections = Array.new(num_connections) {send_http "GET / HTTP/1.0\r\n\r\n"}
    @server.stop
    wait.close
    bad = 0
    connections.each do |s|
      begin
        assert_match 'DONE', s.read
      rescue Errno::ECONNRESET
        bad += 1
      end
    end
    if drain
      assert_equal 0, bad
    else
      refute_equal 0, bad
    end
  end

  def test_not_drain_on_shutdown
    test_drain_on_shutdown false
  end

  def test_remote_address_header
    server_run(remote_address: :header, remote_address_header: 'HTTP_X_REMOTE_IP') do |env|
      [200, {}, [env['REMOTE_ADDR']]]
    end
    remote_addr = send_http_and_read("GET / HTTP/1.1\r\nX-Remote-IP: 1.2.3.4\r\n\r\n").split("\r\n").last
    assert_equal '1.2.3.4', remote_addr

    # TODO: it would be great to test a connection from a non-localhost IP, but we can't really do that. For
    # now, at least test that it doesn't return garbage.
    remote_addr = send_http_and_sysread("GET / HTTP/1.1\r\n\r\n").split("\r\n").last
    assert_equal @host, remote_addr
  end

  def get_chunk_times
    body = +''
    times = []
    Net::HTTP.start @host, @port do |http|
      req = Net::HTTP::Get.new '/'
      http.request req do |resp|
        resp.read_body do |chunk|
          next if chunk.empty?
          body << chunk
          times << Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

      end
    end
    [body, times]
  end

  # see https://github.com/sinatra/sinatra/blob/master/examples/stream.ru
  def test_streaming_enum_body_1
    str = "Hello Puma World"
    body_len = str.bytesize * 3

    server_run do |env|
      hdrs = {}
      hdrs['Content-Type'] = "text; charset=utf-8"

      body = Enumerator.new do |yielder|
          yielder << str
          sleep 0.5
          yielder << str
          sleep 1.5
          yielder << str
      end
      [200, hdrs, body]
    end

    resp_body, times = get_chunk_times
    assert_equal body_len, resp_body.bytesize
    assert_equal str * 3, resp_body
    assert times[1] - times[0] > 0.4
    assert times[1] - times[0] < 1
    assert times[2] - times[1] > 1
  end

  # similar to a longer running app passing its output thru an enum body
  # example - https://github.com/dentarg/testssl.web
  def test_streaming_enum_body_2
    str = "Hello Puma World"
    loops = 10
    body_len = str.bytesize * loops

    server_run do |env|
      hdrs = {}
      hdrs['Content-Type'] = "text; charset=utf-8"

      body = Enumerator.new do |yielder|
        loops.times do |i|
          sleep 0.15 unless i.zero?
          yielder << str
        end
      end
      [200, hdrs, body]
    end
    resp_body, times = get_chunk_times
    assert_equal body_len, resp_body.bytesize
    assert_equal str * loops, resp_body
    assert_operator times.last - times.first, :>, 1.0
  end
end
