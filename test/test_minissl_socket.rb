# frozen_string_literal: true

require_relative "helper"

if ::Puma::HAS_SSL
  require "puma/minissl"
  require "openssl"
  require "socket"
  require "timeout"
end

class TestMiniSSLSocket < PumaTest
  parallelize_me!

  EXAMPLES = File.expand_path "../examples/puma", __dir__

  def setup
    ctx = Puma::MiniSSL::Context.new
    if Puma.jruby?
      ctx.keystore = "#{EXAMPLES}/keystore.jks"
      ctx.keystore_pass = "jruby_puma"
    else
      ctx.key  = "#{EXAMPLES}/puma_keypair.pem"
      ctx.cert = "#{EXAMPLES}/cert_puma.pem"
    end
    ctx.verify_mode = Puma::MiniSSL::VERIFY_NONE

    listener = TCPServer.new "127.0.0.1", 0
    raw_client = TCPSocket.new "127.0.0.1", listener.addr[1]
    @raw_server = listener.accept
    listener.close
    eng_ctx = Puma.jruby? ? ctx : Puma::MiniSSL::SSLContext.new(ctx)
    @server = Puma::MiniSSL::Socket.new @raw_server, Puma::MiniSSL::Engine.server(eng_ctx)

    client_ctx = OpenSSL::SSL::SSLContext.new
    client_ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
    @client = OpenSSL::SSL::SSLSocket.new raw_client, client_ctx
    @client.sync_close = true

    handshake = Thread.new { @client.connect; @client.write "ping" }
    assert_equal "ping", server_read(4)
    handshake.join
  end

  def teardown
    @client&.close rescue nil
    @server&.close rescue nil
  end

  def server_read(size)
    Timeout.timeout(5) do
      begin
        @server.read_nonblock size
      rescue IO::WaitReadable
        @raw_server.wait_readable 1
        retry
      end
    end
  end

  def fill_until_eagain(chunk)
    Timeout.timeout(5) do
      loop { @server.write_nonblock chunk }
    rescue IO::EAGAINWaitWritable
    end
  rescue Timeout::Error
    flunk "write_nonblock blocked on a peer that isn't reading"
  end

  def test_write_nonblock_raises_eagain_when_peer_does_not_read
    fill_until_eagain "x" * 64 * 1024

    assert_raises(IO::EAGAINWaitWritable) { @server.write_nonblock "y" }
  end

  def test_write_nonblock_exception_false_returns_wait_writable
    fill_until_eagain "x" * 64 * 1024

    assert_equal :wait_writable, @server.write_nonblock("y" * 64 * 1024, exception: false)
  end

  def test_write_nonblock_retry_delivers_data_once
    assert_retries_deliver_data_once Random.new(42).bytes(16 * 1024 * 1024)
  end

  def test_write_nonblock_retry_delivers_multibyte_data_once
    assert_retries_deliver_data_once "\u20ac" * 2 * 1024 * 1024
  end

  def assert_retries_deliver_data_once(data)
    received = +""
    reader = Thread.new do
      sleep 0.2 # let the writer hit EAGAIN first
      received << @client.readpartial(64 * 1024) while received.bytesize < data.bytesize
    end

    eagain = 0
    n = 0
    Timeout.timeout(10) do
      while n < data.bytesize
        begin
          n += @server.write_nonblock(data.byteslice(n..-1))
        rescue IO::EAGAINWaitWritable
          eagain += 1
          assert @server.wait_writable(5), "wait_writable timed out"
          retry
        end
      end
    end
    reader.join 10

    assert_operator eagain, :>, 0
    assert_equal data.bytesize, received.bytesize
    assert_equal data.b, received.b
  end

  def test_write_after_eagain_sends_pending_ciphertext_first
    fill_until_eagain "x" * 64 * 1024
    reader = Thread.new do
      buf = +""
      buf << @client.readpartial(64 * 1024) until buf.end_with?("tail")
      buf
    end

    @server.write "tail"

    assert_match(/x+tail\z/, reader.value)

    assert_equal 4, @server.write_nonblock("next")
    assert_equal "next", @client.readpartial(4)
  end

  def test_write_between_write_nonblock_retries_keeps_data_in_order
    sent = +""
    frame = nil
    index = 0
    loop do
      frame = format("%08d", index) * 2_000
      begin
        @server.write_nonblock frame
      rescue IO::EAGAINWaitWritable
        break
      end
      sent << frame
      index += 1
    end
    sent << frame << "marker" << "end"

    reader = Thread.new { @client.read sent.bytesize }
    Timeout.timeout(5) do
      @server.write "marker"
      begin
        @server.write_nonblock frame
      rescue IO::EAGAINWaitWritable
        @server.wait_writable 1
        retry
      end
      @server.write "end"
    end

    received = reader.value
    assert_equal sent.bytesize, received.bytesize
    assert received == sent, "TLS data arrived out of order or duplicated"
  end

  def test_empty_write_nonblock_keeps_pending_write
    chunk = "x" * 64 * 1024
    sent = 0
    n = nil
    sent += n until (n = @server.write_nonblock(chunk, exception: false)) == :wait_writable

    assert_equal 0, @server.write_nonblock("")

    reader = Thread.new do
      buf = +""
      buf << @client.readpartial(64 * 1024) until buf.end_with?("end")
      buf
    end
    Timeout.timeout(5) do
      @server.wait_writable 1 while (n = @server.write_nonblock(chunk, exception: false)) == :wait_writable
      sent += n
      @server.write "end"
    end

    assert_equal sent + 3, reader.value.bytesize
  end

  def test_wait_writable
    assert @server.wait_writable(1)

    fill_until_eagain "x" * 64 * 1024
    sleep 0.05
    fill_until_eagain "x" * 64 * 1024

    refute @server.wait_writable(0.1)
  end

  def test_close_does_not_block_when_peer_does_not_read
    fill_until_eagain "x" * 64 * 1024

    Timeout.timeout(2) { @server.close }

    assert_predicate @raw_server, :closed?
  rescue Timeout::Error
    flunk "close blocked on a peer that isn't reading"
  end

  def test_close_sends_close_notify
    @server.close

    assert_raises(EOFError) { Timeout.timeout(2) { @client.sysread 16 } }
  end
end if ::Puma::HAS_SSL
