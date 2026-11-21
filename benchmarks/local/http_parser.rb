# frozen_string_literal: true

# Compares the C extension's HTTP parser with Puma::RubyHttpParser: time and
# object allocations per parse, for a few representative requests.
#
#   bundle exec ruby --yjit -Ilib benchmarks/local/http_parser.rb [seconds per case]
#
# Each parse starts from a fresh env hash and a binary copy of the request, as
# Puma's client does; that baseline cost is measured separately and
# subtracted. The copy must own its bytes: the C parser upcases header names
# in place, and writes through to any string a copy-on-write #dup shares
# memory with.

require "puma"

abort "The C extension is not loaded, so there is nothing to compare against." unless defined?(Puma::NativeHttpParser)

BROWSER_GET = <<~REQ.gsub("\n", "\r\n")
  GET /products/42?ref=home&utm_source=newsletter HTTP/1.1
  Host: www.example.com
  Connection: keep-alive
  sec-ch-ua: "Chromium";v="130", "Google Chrome";v="130", "Not?A_Brand";v="99"
  sec-ch-ua-mobile: ?0
  sec-ch-ua-platform: "macOS"
  Upgrade-Insecure-Requests: 1
  User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36
  Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7
  Sec-Fetch-Site: same-origin
  Sec-Fetch-Mode: navigate
  Sec-Fetch-User: ?1
  Sec-Fetch-Dest: document
  Referer: https://www.example.com/products?page=2
  Accept-Encoding: gzip, deflate, br, zstd
  Accept-Language: en-AU,en-GB;q=0.9,en;q=0.8
  Cookie: _ga=GA1.1.1234567890.1700000000; _example_session=3f2a9c1e8b7d4a6f0e5c2b1a9d8c7e6f5a4b3c2d1e0f9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e0f; theme=dark; locale=en-AU
  If-None-Match: W/"5d41402abc4b2a76b9719d911017c592"

REQ

API_POST = <<~REQ.gsub("\n", "\r\n") + '{"name":"widget","qty":3}'
  POST /api/v1/orders HTTP/1.1
  Host: api.example.com
  User-Agent: example-client/2.4.1
  Accept: application/json
  Content-Type: application/json
  Content-Length: 25
  Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U
  X-Request-Id: 9b2f6c1e-3a4d-4e5f-8a7b-1c2d3e4f5a6b

REQ

MINIMAL = "GET / HTTP/1.1\r\nHost: localhost:9292\r\n\r\n"

CASES = {
  "browser GET (#{BROWSER_GET.bytesize} B, 17 headers)" => BROWSER_GET,
  "API POST (#{API_POST.bytesize} B, 7 headers)" => API_POST,
  "minimal GET (#{MINIMAL.bytesize} B, 1 header)" => MINIMAL,
}.transform_values { |request| request.b.freeze }.freeze

PARSERS = {"C" => Puma::NativeHttpParser, "Ruby" => Puma::RubyHttpParser}.freeze

def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

# Runs +iterations+ parses, or only the per-parse setup when +parser+ is nil,
# so the setup can be subtracted.
def run(parser, request, iterations)
  i = 0
  while i < iterations
    env = {}
    buf = String.new(capacity: request.bytesize) << request
    if parser
      parser.reset
      parser.execute(env, buf, 0)
    end
    i += 1
  end
end

# Median seconds per parse over several timed rounds.
def time_per_parse(parser, request, seconds)
  batch = 2_000
  run(parser, request, batch * 5) # warm up, and let YJIT compile
  rounds = []
  deadline = clock + seconds
  while clock < deadline || rounds.size < 5
    t = clock
    run(parser, request, batch)
    rounds << (clock - t) / batch
  end
  rounds.sort[rounds.size / 2]
end

def allocations_per_parse(parser, request)
  n = 10_000
  run(parser, request, 100)
  before = GC.stat(:total_allocated_objects)
  run(parser, request, n)
  (GC.stat(:total_allocated_objects) - before).fdiv(n)
end

# Parse once with each parser before anything is timed, while this code is
# still interpreted. If YJIT compiles RubyHttpParser#execute before it has
# ever run, as happens when an already compiled loop makes the first call,
# the compiled method stays about as slow as the interpreter. In a server the
# first requests are interpreted, so this matches what Puma sees.
CASES.each_value do |request|
  PARSERS.each_value { |klass| klass.new.execute({}, String.new(capacity: request.bytesize) << request, 0) }
end

seconds = Float(ARGV.fetch(0, "3"))
yjit = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?
puts RUBY_DESCRIPTION
puts "YJIT #{yjit ? 'on' : 'off'}; median of timed rounds, #{seconds}s per case; setup (env hash + buffer copy) subtracted"
puts

CASES.each do |label, request|
  base_time = time_per_parse(nil, request, seconds / 2)
  base_allocs = allocations_per_parse(nil, request)
  puts label
  results = PARSERS.to_h do |name, klass|
    parser = klass.new
    t = time_per_parse(parser, request, seconds) - base_time
    a = allocations_per_parse(parser, request) - base_allocs
    printf "  %-5s %8.2f µs/parse  %6.1f objects/parse\n", name, t * 1e6, a
    [name, t]
  end
  printf "  Ruby parser adds %.2f µs per request (%.1fx the C parser)\n\n",
    (results["Ruby"] - results["C"]) * 1e6, results["Ruby"] / results["C"]
end
