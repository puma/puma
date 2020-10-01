require 'puma/events'
require_relative "helper"

class TestEvents < Minitest::Test
  def test_null
    events = Puma::Events.null

    assert_instance_of Puma::NullIO, events.stdout
    assert_instance_of Puma::NullIO, events.stderr
    assert_equal events.stdout, events.stderr
  end

  def test_strings
    events = Puma::Events.strings

    assert_instance_of StringIO, events.stdout
    assert_instance_of StringIO, events.stderr
  end

  def test_stdio
    events = Puma::Events.stdio

    assert_equal STDOUT, events.stdout
    assert_equal STDERR, events.stderr
  end

  def test_register_callback_with_block
    res = false

    events = Puma::Events.null

    events.register(:exec) { res = true }

    events.fire(:exec)

    assert_equal true, res
  end

  def test_register_callback_with_object
    obj = Object.new

    def obj.res
      @res || false
    end

    def obj.call
      @res = true
    end

    events = Puma::Events.null

    events.register(:exec, obj)

    events.fire(:exec)

    assert_equal true, obj.res
  end

  def test_fire_callback_with_multiple_arguments
    res = []

    events = Puma::Events.null

    events.register(:exec) { |*args| res.concat(args) }

    events.fire(:exec, :foo, :bar, :baz)

    assert_equal [:foo, :bar, :baz], res
  end

  def test_on_booted_callback
    res = false

    events = Puma::Events.null

    events.on_booted { res = true }

    events.fire_on_booted!

    assert res
  end

  def test_log_writes_to_stdout
    out, _ = capture_io do
      Puma::Events.stdio.log("ready")
    end

    assert_equal "ready\n", out
  end

  def test_write_writes_to_stdout
    out, _ = capture_io do
      Puma::Events.stdio.write("ready")
    end

    assert_equal "ready", out
  end

  def test_debug_writes_to_stdout_if_env_is_present
    original_debug, ENV["PUMA_DEBUG"] = ENV["PUMA_DEBUG"], "1"

    out, _ = capture_io do
      Puma::Events.stdio.debug("ready")
    end

    assert_equal "% ready\n", out
  ensure
    ENV["PUMA_DEBUG"] = original_debug
  end

  def test_debug_not_write_to_stdout_if_env_is_not_present
    out, _ = capture_io do
      Puma::Events.stdio.debug("ready")
    end

    assert_empty out
  end

  def test_error_writes_to_stderr_and_exits
    did_exit = false

    _, err = capture_io do
      begin
        Puma::Events.stdio.error("interrupted")
      rescue SystemExit
        did_exit = true
      ensure
        assert did_exit
      end
    end

    assert_match %r!ERROR: interrupted!, err
  end

  def test_pid_formatter
    pid = Process.pid

    out, _ = capture_io do
      events = Puma::Events.stdio

      events.formatter = Puma::Events::PidFormatter.new

      events.write("ready")
    end

    assert_equal "[#{ pid }] ready", out
  end

  def test_custom_log_formatter
    custom_formatter = proc { |str| "-> #{ str }" }

    out, _ = capture_io do
      events = Puma::Events.stdio

      events.formatter = custom_formatter

      events.write("ready")
    end

    assert_equal "-> ready", out
  end

  def test_parse_error
    port = 0
    host = "127.0.0.1"
    app = proc { |env| [200, {"Content-Type" => "plain/text"}, ["hello\n"]] }
    events = Puma::Events.strings
    server = Puma::Server.new app, events

    port = (server.add_tcp_listener host, 0).addr[1]
    server.run

    sock = TCPSocket.new host, port
    path = "/"
    params = "a"*1024*10

    sock.syswrite "GET #{path}?a=#{params} HTTP/1.1\r\nConnection: close\r\n\r\n"
    sock.read
    sleep 0.1 # important so that the previous data is sent as a packet
    assert_match %r!HTTP parse error, malformed request!, events.stderr.string
    assert_match %r!\("GET #{path}" - \(-\)\)!, events.stderr.string
  ensure
    sock.close if sock && !sock.closed?
    server.stop true
  end

  # test_puma_server_ssl.rb checks that ssl errors are raised correctly,
  # but it mocks the actual error code.  This test the code, but it will
  # break if the logged message changes
  def test_ssl_error
    events = Puma::Events.strings

    ssl_mock = -> (addr, subj) {
      obj = Object.new
      obj.define_singleton_method(:peeraddr) { addr }
      if subj
        cert = Object.new
        cert.define_singleton_method(:subject) { subj }
        obj.define_singleton_method(:peercert) { cert }
      else
        obj.define_singleton_method(:peercert) { nil }
      end
      obj
    }

    events.ssl_error OpenSSL::SSL::SSLError, ssl_mock.call(['127.0.0.1'], 'test_cert')
    error = events.stderr.string
    assert_includes error, "SSL error"
    assert_includes error, "peer: 127.0.0.1"
    assert_includes error, "cert: test_cert"

    events.stderr.string = ''

    events.ssl_error OpenSSL::SSL::SSLError, ssl_mock.call(nil, nil)
    error = events.stderr.string
    assert_includes error, "SSL error"
    assert_includes error, "peer: <unknown>"
    assert_includes error, "cert: :"

  end if ::Puma::HAS_SSL
end
