# frozen_string_literal: true

require_relative "duel_helper"

# Puma::HttpParser, the C extension (Ragel's state machine and its
# callbacks), parsing a request's head into a fresh env, as Puma::Client
# does for every request. A client keeps its parser and resets it for
# each request, as these do. Each parse is of a fresh copy of the bytes,
# as each read from a socket is (see fresh in duel_helper.rb).

def parse(parser, request)
  parser.reset
  parser.execute({}, fresh(request), 0)
end

duel "parser: a small GET" do
  once do
    @parser = Puma::HttpParser.new
    @request = http_request("GET", "/", headers: curl_headers)
  end
  parse(@parser, @request)
end

duel "parser: a browser's GET with 16 headers" do
  once do
    @parser = Puma::HttpParser.new
    @request = http_request("GET", "/dashboard/projects/42?tab=activity&page=2", headers: browser_headers)
  end
  parse(@parser, @request)
end

duel "parser: a GET with 40 headers" do
  once do
    @parser = Puma::HttpParser.new
    @request = http_request("GET", "/", headers: many_headers(40))
  end
  parse(@parser, @request)
end

duel "parser: a GET with a 4 KB cookie" do
  once do
    @parser = Puma::HttpParser.new
    cookie = Array.new(64) { |i| "cookie_#{i}=#{'v' * 48}" }.join("; ")
    @request = http_request("GET", "/", headers: curl_headers.merge("Cookie" => cookie))
  end
  parse(@parser, @request)
end

duel "parser: a GET with a 2 KB query string" do
  once do
    @parser = Puma::HttpParser.new
    query = Array.new(100) { |i| "key#{i}=value#{i}abc" }.join("&")
    @request = http_request("GET", "/search?#{query}", headers: curl_headers)
  end
  parse(@parser, @request)
end

duel "parser: a GET with repeated headers" do
  once do
    @parser = Puma::HttpParser.new
    head = http_request("GET", "/", headers: curl_headers).delete_suffix("\r\n")
    @request = head + Array.new(10) { |i| "Accept-Language: lang-#{i}\r\nX-Forwarded-For: 10.0.0.#{i}\r\n" }.join + "\r\n"
  end
  parse(@parser, @request)
end

duel "parser: the head of a POST with its body" do
  once do
    @parser = Puma::HttpParser.new
    @request = http_request("POST", "/api/v1/users", headers: api_headers, body: json_document(10))
  end
  parse(@parser, @request)
  @parser.body
end

duel "parser: a head that arrives in two reads" do
  once do
    @parser = Puma::HttpParser.new
    @request = http_request("GET", "/dashboard/projects/42?tab=activity&page=2", headers: browser_headers)
    @first = @request.byteslice(0, @request.bytesize / 2)
    @rest = @request.byteslice(@first.bytesize..)
  end
  @parser.reset
  env = {}
  buffer = fresh(@first)
  nread = @parser.execute(env, buffer, 0)
  @parser.execute(env, buffer << @rest, nread)
end
