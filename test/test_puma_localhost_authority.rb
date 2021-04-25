# Nothing in this file runs if Puma isn't compiled with ssl support
#
# helper is required first since it loads Puma, which needs to be
# loaded so HAS_SSL is defined
require_relative "helper"

if ::Puma::HAS_SSL
  require "puma/events"
  require "net/http"
  require "localhost/authority"

  class SSLEventsHelper < ::Puma::Events
    attr_accessor :addr, :cert, :error

    def ssl_error(error, ssl_socket)
      self.error = error
      self.addr = ssl_socket.peeraddr.last rescue "<unknown>"
      self.cert = ssl_socket.peercert
    end
  end

  # net/http (loaded in helper) does not necessarily load OpenSSL
  require "openssl" unless Object.const_defined? :OpenSSL

  puts "", RUBY_DESCRIPTION, "RUBYOPT: #{ENV['RUBYOPT']}",
    "                         OpenSSL",
    "OPENSSL_LIBRARY_VERSION: #{OpenSSL::OPENSSL_LIBRARY_VERSION}",
    "        OPENSSL_VERSION: #{OpenSSL::OPENSSL_VERSION}", ""
end

class TestPumaLocalhostAuthority < Minitest::Test
  parallelize_me!
  def setup
    @http = nil
    @server = nil
  end

  def teardown
    @http.finish if @http && @http.started?
    @server.stop(true) if @server
  end

  # yields ctx to block, use for ctx setup & configuration
  def start_server
    @host = "127.0.0.1"
    app = lambda { |env| [200, {}, [env['rack.url_scheme']]] }

    @events = SSLEventsHelper.new STDOUT, STDERR

    @server = Puma::Server.new app, @events
    @server.app = app
    @port = (@server.add_ssl_listener @host, 0,nil).addr[1]

    @http = Net::HTTP.new @host, @port
    @http.use_ssl = true
    # Disabling verification since its self signed
    @http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    # @http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    @server.run
  end

  def test_url_scheme_for_https
    start_server
    body = nil
    @http.start do
      req = Net::HTTP::Get.new "/", {}
      @http.request(req) do |rep|
        body = rep.body
      end
    end

    assert_equal "https", body
  end

  def test_request_wont_block_thread
    start_server
    # Open a connection and give enough data to trigger a read, then wait
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
    port = @server.connected_ports[0]
    socket = OpenSSL::SSL::SSLSocket.new TCPSocket.new(@host, port), ctx
    socket.connect
    socket.write "HEAD"
    sleep 0.1

    # Capture the amount of threads being used after connecting and being idle
    thread_pool = @server.instance_variable_get(:@thread_pool)
    busy_threads = thread_pool.spawned - thread_pool.waiting

    socket.close

    # The thread pool should be empty since the request would block on read
    # and our request should have been moved to the reactor.
    assert busy_threads.zero?, "Our connection is monopolizing a thread"
  end

  def test_very_large_return
    start_server
    giant = "x" * 2056610
    @server.app = proc do
      [200, {}, [giant]]
    end

    body = nil
    @http.start do
      req = Net::HTTP::Get.new "/"
      @http.request(req) do |rep|
        body = rep.body
      end
    end

    assert_equal giant.bytesize, body.bytesize
  end

  def test_form_submit
    start_server
    body = nil
    @http.start do
      req = Net::HTTP::Post.new '/'
      req.set_form_data('a' => '1', 'b' => '2')

      @http.request(req) do |rep|
        body = rep.body
      end

    end

    assert_equal "https", body
  end

  def test_http_rejection
    body_http  = nil
    body_https = nil
    start_server
    http = Net::HTTP.new @host, @server.connected_ports[0]
    http.use_ssl = false
    http.read_timeout = 6

    tcp = Thread.new do
      req_http = Net::HTTP::Get.new "/", {}
      # Net::ReadTimeout - TruffleRuby
      assert_raises(Errno::ECONNREFUSED, EOFError, Net::ReadTimeout) do
        http.start.request(req_http) { |rep| body_http = rep.body }
      end
    end

    ssl = Thread.new do
      @http.start do
        req_https = Net::HTTP::Get.new "/", {}
        @http.request(req_https) { |rep_https| body_https = rep_https.body }
      end
    end

    tcp.join
    ssl.join
    http.finish
    sleep 1.0

    assert_nil body_http
    assert_equal "https", body_https

    thread_pool = @server.instance_variable_get(:@thread_pool)
    busy_threads = thread_pool.spawned - thread_pool.waiting

    assert busy_threads.zero?, "Our connection is wasn't dropped"
  end
end if ::Puma::HAS_SSL
