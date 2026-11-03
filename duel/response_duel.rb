# frozen_string_literal: true

require_relative "duel_helper"

# Writing a Rack app's response (Puma::Response#prepare_response): the
# status line, each header checked and written, the framing (a
# Content-Length, or chunked), and the body, through the client's
# IOBuffer into the socket. Each benchmark parses its request once, and
# writes the response to a MemorySocket, which keeps no bytes.

def respond(status, headers, body)
  @server.prepare_response(status, headers, body, 1, @client)
end

def reading(request)
  @server = puma_server
  @client = read_request(@server, request)
end

duel "response: a 200 with a small body" do
  once do
    reading(http_request("GET", "/", headers: curl_headers))
    @headers = { "content-type" => "text/plain" }
  end
  respond(200, @headers, ["Hello World"])
end

duel "response: a 200 with a Rails app's headers" do
  once do
    reading(http_request("GET", "/dashboard", headers: browser_headers))
    @headers = rails_response_headers
    @body = text_of(4096)
  end
  respond(200, @headers, [@body])
end

duel "response: a 404" do
  once do
    reading(http_request("GET", "/missing", headers: curl_headers))
    @headers = { "content-type" => "text/html; charset=utf-8" }
  end
  respond(404, @headers, ["Not Found"])
end

duel "response: 30 long headers" do
  once do
    reading(http_request("GET", "/", headers: curl_headers))
    # As test/rackup/many_long_headers.ru, which benchmarks/wrk measures.
    @headers = Array.new(30) { |i| ["x-my-header-#{i}", format("%02d", i) * 1000] }.to_h
  end
  respond(200, @headers, ["Hello World"])
end

duel "response: headers with several values" do
  once do
    reading(http_request("GET", "/", headers: curl_headers))
    @headers = {
      "content-type" => "text/html",
      "set-cookie"   => "_session_id=5d41402abc4b2a76b9719d911017c592; path=/; HttpOnly\n" \
                        "theme=dark; path=/\nlocale=en; path=/",
      "vary"         => ["Accept", "Accept-Encoding", "Origin"],
      "link"         => ["</app.css>; rel=preload; as=style", "</app.js>; rel=preload; as=script"]
    }
  end
  respond(200, @headers, ["Hello World"])
end

duel "response: a 64 KB body" do
  once do
    reading(http_request("GET", "/", headers: curl_headers))
    @headers = { "content-type" => "text/plain" }
    @body = text_of(64 * 1024)
  end
  respond(200, @headers, [@body])
end

duel "response: a body of 100 parts" do
  once do
    reading(http_request("GET", "/", headers: curl_headers))
    @headers = { "content-type" => "text/html" }
    @body = Array.new(100) { |i| "<li>item #{i}</li>\n" }
  end
  respond(200, @headers, @body)
end

duel "response: a streamed body, chunked" do
  once do
    reading(http_request("GET", "/", headers: curl_headers))
    @headers = { "content-type" => "text/plain" }
    @body = StreamedBody.new(Array.new(16) { text_of(1024) })
  end
  respond(200, @headers, @body)
end

duel "response: a 304 with no body" do
  once do
    reading(http_request("GET", "/", headers: curl_headers.merge("If-None-Match" => '"abc"')))
    @headers = { "etag" => '"abc"', "cache-control" => "max-age=60" }
  end
  respond(304, @headers, [])
end

duel "response: a HEAD request" do
  once do
    reading(http_request("HEAD", "/", headers: curl_headers))
    @headers = { "content-type" => "text/plain", "content-length" => "11" }
  end
  respond(200, @headers, [])
end

duel "response: an HTTP/1.0 keep-alive request" do
  once do
    request = http_request("GET", "/", headers: curl_headers.merge("Connection" => "keep-alive"))
    reading(request.sub("HTTP/1.1", "HTTP/1.0"))
    @headers = { "content-type" => "text/plain" }
  end
  respond(200, @headers, ["Hello World"])
end
