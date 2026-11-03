# frozen_string_literal: true

require "puma/server"
require "socket"

# A stand-in for a client's socket: it serves a fixed request from memory,
# and counts what's written back and keeps none of it. Puma reads and
# writes it as it does a TCPSocket (read_nonblock, write_nonblock,
# wait_readable), so a request runs through the parser, Puma::Client and
# the response code without a system call, and times steadily.
class MemorySocket
  PEERADDR = ["AF_INET", 54_321, "127.0.0.1", "127.0.0.1"].freeze

  attr_reader :written

  def initialize(request = "")
    @request = request.b.freeze
    @offset = 0
    @written = 0
    @closed = false
  end

  # Serves the same request again, from its start.
  def rewind
    @offset = 0
    @written = 0
    @closed = false
    self
  end

  def to_io
    self
  end

  def read_nonblock(size, buffer = nil, exception: true)
    if @offset >= @request.bytesize
      return :wait_readable unless exception

      raise IO::EAGAINWaitReadable
    end

    chunk = @request.byteslice(@offset, size)
    @offset += chunk.bytesize
    # A copy of its own, as a socket reads into, since the parser rewrites
    # header names in the buffer it parses (see #fresh).
    buffer ? buffer.clear << chunk : fresh(chunk)
  end

  def wait_readable(_timeout = nil)
    @offset < @request.bytesize ? self : nil
  end

  def write_nonblock(data, exception: true)
    @written += data.bytesize
    data.bytesize
  end

  def write(*data)
    data.sum { |str| write_nonblock(str) }
  end

  def <<(data)
    write_nonblock(data)
    self
  end

  def flush
    self
  end

  def peeraddr
    PEERADDR
  end

  def close
    @closed = true
  end

  def closed?
    @closed
  end
end

# A copy of the string with its own bytes. Puma::HttpParser upcases a
# header's name in the very buffer it parses (without unsharing it), so
# parsing a dup, which shares its bytes, would change the original.
def fresh(string)
  String.new(capacity: string.bytesize) << string
end

# The options a server is made with: a pool of one thread, as `puma -t 1`,
# and nothing logged.
def server_options
  { min_threads: 1, max_threads: 1, log_writer: Puma::LogWriter.null }
end

# A server for this Rack app, not started: enough for Puma::Client and
# for writing responses.
def puma_server(app = ->(_env) { [200, {}, ["OK"]] })
  Puma::Server.new(app, nil, server_options)
end

# A Puma::Client for this request, as the server makes one for a new
# connection.
def puma_client(server, request)
  server.new_client(MemorySocket.new(request), nil)
end

# Reads and parses this request through a fresh Puma::Client, as for a
# new connection, and returns the client.
def read_request(server, request)
  client = puma_client(server, request)
  raise "the request didn't finish" unless client.eagerly_finish

  client
end

# The bytes of an HTTP/1.1 request with these headers and body. With
# chunks, the body is sent chunked, in chunks of that many bytes.
def http_request(method = "GET", target = "/", headers: {}, body: nil, chunks: nil)
  head = +"#{method} #{target} HTTP/1.1\r\n"
  headers.each { |name, value| head << "#{name}: #{value}\r\n" }
  if body && chunks
    head << "Transfer-Encoding: chunked\r\n\r\n"
    slices(body.b, chunks).each { |chunk| head << "#{chunk.bytesize.to_s(16)}\r\n#{chunk}\r\n" }
    head << "0\r\n\r\n"
  elsif body
    head << "Content-Length: #{body.bytesize}\r\n\r\n" << body.b
  else
    head << "\r\n"
  end
  head.b
end

# The string, in slices of up to this many bytes.
def slices(string, size)
  (0...string.bytesize).step(size).map { |offset| string.byteslice(offset, size) }
end

# The headers of a small request, as curl sends them.
def curl_headers
  { "Host" => "example.com", "User-Agent" => "curl/8.7.1", "Accept" => "*/*" }
end

# The headers of a page request from a browser behind a proxy.
def browser_headers
  {
    "Host"                      => "app.example.com",
    "User-Agent"                => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
                                   "(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36",
    "Accept"                    => "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,*/*;q=0.8",
    "Accept-Encoding"           => "gzip, deflate, br, zstd",
    "Accept-Language"           => "en-US,en;q=0.9",
    "Cache-Control"             => "max-age=0",
    "Connection"                => "keep-alive",
    "Cookie"                    => "_session_id=5d41402abc4b2a76b9719d911017c592; theme=dark; locale=en",
    "Referer"                   => "https://app.example.com/dashboard",
    "Sec-Fetch-Dest"            => "document",
    "Sec-Fetch-Mode"            => "navigate",
    "Sec-Fetch-Site"            => "same-origin",
    "Upgrade-Insecure-Requests" => "1",
    "X-Forwarded-For"           => "203.0.113.7, 10.0.0.2",
    "X-Forwarded-Proto"         => "https",
    "X-Request-Id"              => "0f8fad5b-d9cb-469f-a165-70867728950e"
  }
end

# The headers of a JSON API request.
def api_headers
  {
    "Host"          => "api.example.com",
    "User-Agent"    => "MyApp/1.0",
    "Accept"        => "application/json",
    "Authorization" => "Bearer abc123def456",
    "Content-Type"  => "application/json"
  }
end

# Many headers, most of them ones the parser has no interned name for.
def many_headers(count)
  curl_headers.merge(Array.new(count - curl_headers.size) { |i| ["X-Custom-Header-#{i}", "value-#{i}-abcdef"] }.to_h)
end

# A JSON document of this many records, about 100 bytes each.
def json_document(records)
  items = Array.new(records) do |i|
    %({"id":#{i},"name":"user#{i}","email":"user#{i}@example.com","active":true,"score":#{(i * 7) % 100}})
  end
  "[#{items.join(',')}]"
end

# Text of this many bytes, the same every time.
def text_of(bytes)
  line = "The quick brown fox jumps over the lazy dog. 0123456789\n"
  (line * ((bytes / line.bytesize) + 1)).byteslice(0, bytes)
end

# The headers of a typical response from a Rails app.
def rails_response_headers
  {
    "content-type"              => "text/html; charset=utf-8",
    "cache-control"             => "max-age=0, private, must-revalidate",
    "etag"                      => 'W/"5d41402abc4b2a76b9719d911017c592"',
    "vary"                      => "Accept, Accept-Encoding",
    "x-request-id"              => "0f8fad5b-d9cb-469f-a165-70867728950e",
    "x-runtime"                 => "0.012345",
    "x-frame-options"           => "SAMEORIGIN",
    "x-content-type-options"    => "nosniff",
    "referrer-policy"           => "strict-origin-when-cross-origin",
    "strict-transport-security" => "max-age=31536000; includeSubDomains"
  }
end

# A body that yields its parts, as a streamed Rack body does, with no
# length known in advance, so Puma sends it chunked.
class StreamedBody
  def initialize(parts)
    @parts = parts
  end

  def each(&block)
    @parts.each(&block)
  end
end
