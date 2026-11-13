# frozen_string_literal: true

require_relative "helper"

if ::Puma::HAS_SSL
  require "puma/minissl"
  require "openssl"
  require "rbconfig"
  require "shellwords"
  require "tmpdir"
  require_relative "helpers/test_puma/puma_socket"
end

class TestPumaServerSSLKeyUpdate < PumaTest
  include TestPuma
  include TestPuma::PumaSocket

  PEER_SOURCE = <<~C
    #include <openssl/ssl.h>
    #include <netinet/in.h>
    #include <arpa/inet.h>
    #include <sys/socket.h>
    #include <stdlib.h>
    #include <string.h>
    #include <signal.h>

    int main(int argc, char **argv) {
      signal(SIGPIPE, SIG_IGN);
      int fd = socket(AF_INET, SOCK_STREAM, 0);
      struct sockaddr_in addr = { .sin_family = AF_INET, .sin_port = htons(atoi(argv[2])) };
      if (inet_pton(AF_INET, argv[1], &addr.sin_addr) != 1) return 2;
      if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) return 3;
      SSL_CTX *ctx = SSL_CTX_new(TLS_client_method());
      SSL_CTX_set_min_proto_version(ctx, TLS1_3_VERSION);
      SSL *ssl = SSL_new(ctx);
      SSL_set_fd(ssl, fd);
      if (SSL_connect(ssl) != 1) return 4;
      int len = strlen(argv[3]);
      if (SSL_write(ssl, argv[3], len) != len) return 5;
      int type = atoi(argv[4]) ? SSL_KEY_UPDATE_REQUESTED : SSL_KEY_UPDATE_NOT_REQUESTED;
      while (SSL_key_update(ssl, type) == 1 && SSL_do_handshake(ssl) == 1);
      return 0;
    }
  C

  REQUESTS = {
    header: "GET /",
    body: "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 10\r\n\r\n",
    continue: "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 10\r\nExpect: 100-continue\r\n\r\n",
  }

  FIRST_DATA_TIMEOUT = 1

  def self.peer
    return @peer if defined?(@peer)

    @peer = nil
    dir = Dir.mktmpdir
    Minitest.after_run { FileUtils.rm_rf dir }
    src = File.join dir, "peer.c"
    File.write src, PEER_SOURCE
    exe = File.join dir, "peer"
    flags = Shellwords.split(ENV.fetch("PUMA_TEST_OPENSSL_FLAGS") { openssl_flags })
    ok = system(RbConfig::CONFIG["CC"], src, "-o", exe, *flags, "-lssl", "-lcrypto", out: File::NULL, err: File::NULL)
    @peer = exe if ok
  rescue SystemCallError
    @peer = nil
  end

  def self.openssl_flags
    dir = RbConfig::CONFIG["configure_args"].to_s[/--with-openssl-dir=(\S+)/, 1]&.delete("'")
    return "-I#{dir}/include -L#{dir}/lib" if dir
    `pkg-config --cflags --libs openssl 2>/dev/null`.strip
  rescue SystemCallError
    ""
  end

  def setup
    skip_if :jruby, :windows
    skip "can't build a C OpenSSL client" unless self.class.peer
    @server = nil
    @pid = nil
  end

  def teardown
    if @pid
      Process.kill :KILL, @pid rescue nil
      Process.wait @pid rescue nil
    end
    @server&.stop true
  end

  def start_server(queue_requests)
    ctx = Puma::MiniSSL::Context.new
    ctx.key  = File.expand_path "../examples/puma/puma_keypair.pem", __dir__
    ctx.cert = File.expand_path "../examples/puma/cert_puma.pem", __dir__
    ctx.verify_mode = Puma::MiniSSL::VERIFY_NONE

    @server = Puma::Server.new ->(_) { [200, {}, ["ok"]] }, nil,
      min_threads: 1, max_threads: 1, queue_requests: queue_requests,
      first_data_timeout: FIRST_DATA_TIMEOUT, log_writer: Puma::LogWriter.strings
    @bind_port = @server.add_ssl_listener(HOST4, 0, ctx).addr[1]
    @server.run
  end

  def assert_peer_closed_and_server_responsive(queue_requests, request, key_update_requested)
    start_server queue_requests
    @pid = Process.spawn self.class.peer, HOST4, @bind_port.to_s, REQUESTS.fetch(request),
      key_update_requested ? "1" : "0", err: File::NULL
    sleep 0.3

    assert_equal "ok", send_http_read_resp_body(host: HOST4, ctx: new_ctx, timeout: 10)

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + FIRST_DATA_TIMEOUT + 10
    sleep 0.1 until Process.wait(@pid, Process::WNOHANG) || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    assert_equal 0, $?&.exitstatus, "connection was not closed"
    @pid = nil

    assert_equal "ok", send_http_read_resp_body(host: HOST4, ctx: new_ctx, timeout: 10)
  end

  [true, false].each do |queue_requests|
    REQUESTS.each_key do |request|
      [true, false].each do |requested|
        mode = queue_requests ? "reactor" : "no_queue"
        define_method :"test_key_updates_#{requested ? "requested" : "not_requested"}_#{request}_#{mode}" do
          assert_peer_closed_and_server_responsive queue_requests, request, requested
        end
      end
    end
  end
end if ::Puma::HAS_SSL
