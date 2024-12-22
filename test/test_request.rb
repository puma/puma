require_relative "helper"

require 'puma/client'
require 'puma/const'
require 'puma/puma_http11'

class TestRequestBase < Minitest::Test
  include Puma::Const

  PEER_ADDR = -> () { ["AF_INET", 80, "127.0.0.1", "127.0.0.1"] }

  def create_client(request, &blk)
    rd, wr = IO.pipe

    rd.define_singleton_method :peeraddr, PEER_ADDR

    env = {}
    wr.write request
    wr.close

    @client = Puma::Client.new rd, env
    @parser = @client.instance_variable_get :@parser
    yield if blk
    @client.eagerly_finish
  end
end

# Tests `Client`'s handling of valid requests by passing it an IO with the
# request string, then checking `env` for keys and/or values
#
class TestRequestValid < TestRequestBase
  def test_no_content
    request = "GET / HTTP/1.1\r\n\r\n"
    create_client request
    if @parser.finished?
      assert_instance_of Puma::NullIO, @client.env['rack.input']
    else
      fail
    end
  end

  def test_content
    request = "GET / HTTP/1.1\r\nContent-Length: 11\r\n\r\nHello World"
    create_client request
    if @parser.finished?
      assert_instance_of Float, @client.env['puma.request_body_wait']
      assert_equal '11', @client.env[CONTENT_LENGTH]
      assert_equal 'Hello World', @client.env['rack.input'].read
    else
      fail
    end
  end

  def test_content_chunked
    request = "GET / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n" \
      "11\r\nTransfer-Encoding\r\n" \
      "11\r\nTransfer-Encoding\r\n" \
      "0\r\n\r\n"
    create_client request
    if @parser.finished?
      assert_instance_of Float, @client.env['puma.request_body_wait']
      refute_operator @client.env, :key?, TRANSFER_ENCODING2
      assert_equal '34', @client.env[CONTENT_LENGTH]
      assert_equal 'Transfer-EncodingTransfer-Encoding', @client.env['rack.input'].read
    else
      fail
    end
  end

  def test_underscore_and_dash
    request = "GET / HTTP/1.1\r\n" \
      "x-forwarded-for: 1.1.1.1\r\n" \
      "x-forwarded_for: 2.2.2.2\r\n" \
      "Content-Length: 11\r\n\r\nHello World"
    create_client request
    if @parser.finished?
      assert_equal "1.1.1.1", @client.env['HTTP_X_FORWARDED_FOR']
    else
      fail
    end
  end

  def test_unmaskable_headers
    request = "GET / HTTP/1.1\r\n" \
      "Transfer_Encoding: chunked\r\n" \
      "Content_Length: 11\r\n\r\nHello World"
    create_client request
    if @parser.finished?
      assert_equal '11', @client.env['HTTP_CONTENT,LENGTH']
      assert_equal 'chunked', @client.env['HTTP_TRANSFER,ENCODING']
    else
      fail
    end
  end
end

# Tests `Client`'s handling of invalid requests by passing it an IO with the
# request string, then checking `env` for keys and/or values
#
class TestRequestInvalid < TestRequestBase
  def test_content_length_oversize
    request = "GET / HTTP/1.1\r\nContent-Length: 11\r\n\r\nHello World"
    assert_raises(Puma::HttpParserError) do
      create_client(request) { @client.http_content_length_limit = 5 }
    end
    assert_equal 413, @client.error_status_code
    assert_equal 'close', @client.env[HTTP_CONNECTION]
  end

  def test_content_length_invalid
    request = "GET / HTTP/1.1\r\nContent-Length: -11\r\n\r\nHello World"
    assert_raises(Puma::HttpParserError) do
      create_client(request)
    end
    assert_equal 400, @client.error_status_code
    assert_equal 'close', @client.env[HTTP_CONNECTION]
  end

  def test_content_chunked_oversize
    request = "GET / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n" \
      "11\r\nTransfer-Encoding\r\n" \
      "11\r\nTransfer-Encoding\r\n" \
      "0\r\n\r\n"
    assert_raises(Puma::HttpParserError) do
      create_client(request) { @client.http_content_length_limit = 16 }
    end
    assert_equal 413, @client.error_status_code
    refute_operator @client.env, :key?, TRANSFER_ENCODING2
    assert_equal 'close', @client.env[HTTP_CONNECTION]
  end
end
