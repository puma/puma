# frozen_string_literal: true

require_relative "duel_helper"

# Puma::Client reading a request from a new connection: the read, the
# parse, checking how the body is framed and reading it, and building the
# Rack env (Puma::ClientEnv). The socket is a MemorySocket (see
# duel_helper.rb), which serves the request from memory, so each
# iteration is a whole new connection's request without a system call.

duel "client: read a small GET" do
  once do
    @server = puma_server
    @request = http_request("GET", "/", headers: curl_headers)
  end
  read_request(@server, @request)
end

duel "client: read a browser's GET with 16 headers" do
  once do
    @server = puma_server
    @request = http_request("GET", "/dashboard/projects/42?tab=activity&page=2", headers: browser_headers)
  end
  read_request(@server, @request)
end

duel "client: read a GET with 40 headers" do
  once do
    @server = puma_server
    @request = http_request("GET", "/", headers: many_headers(40))
  end
  read_request(@server, @request)
end

duel "client: read a GET with underscored headers" do
  once do
    @server = puma_server
    @request = http_request("GET", "/", headers: curl_headers.merge("X_Api_Key" => "abc123", "X_Trace_Id" => "42"))
  end
  read_request(@server, @request)
end

duel "client: read an HTTP/1.0 GET" do
  once do
    @server = puma_server
    @request = http_request("GET", "/", headers: curl_headers).sub("HTTP/1.1", "HTTP/1.0")
  end
  read_request(@server, @request)
end

duel "client: read a POST with a JSON body" do
  once do
    @server = puma_server
    @request = http_request("POST", "/api/v1/users", headers: api_headers, body: json_document(10))
  end
  read_request(@server, @request)
end

duel "client: read a POST with a 96 KB body" do
  once do
    @server = puma_server
    @request = http_request("POST", "/upload", headers: api_headers, body: text_of(96 * 1024))
  end
  read_request(@server, @request)
end

# A chunked body is decoded into a Tempfile, whose creation (a file
# opened and unlinked) is most of the time and too unsteady to judge, so
# this is judged on its counts alone.
duel "client: read a chunked POST of 16 KB", judge: :counted do
  once do
    @server = puma_server
    @request = http_request("POST", "/upload", headers: api_headers, body: text_of(16 * 1024), chunks: 1024)
  end
  read_request(@server, @request).tempfile_close
end

duel "client: read two pipelined requests" do
  once do
    @server = puma_server
    @request = http_request("GET", "/", headers: curl_headers) * 2
  end
  client = read_request(@server, @request)
  client.reset
  client.process_back_to_back_requests
end
