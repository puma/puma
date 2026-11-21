# frozen_string_literal: true

require "puma"

# Differential fuzzer for Puma's two HTTP parsers. It feeds the same input to
# Puma::NativeHttpParser (the C extension) and Puma::RubyHttpParser, in one
# piece or split across several #execute calls, and compares what each parser
# leaves behind after every call: the return value or the error class and
# message, the env (keys, values, encodings, frozenness), #finished?, #error?,
# #nread, #body, and the buffer, which both parsers upcase header names in.
module HttpParserFuzzer
  BINARY = Encoding::BINARY

  GET_PREFIX = "GET / HTTP/1.1\r\nHost: test.com\r\nConnection: close\r\n"

  # Requests from test/test_http11.rb, test/test_request_single.rb and
  # test/test_request_invalid_multiple.rb, with interpolations expanded, plus
  # a few realistic browser and proxy requests.
  SEEDS = [
    "GET /?a=1 HTTP/1.1\r\n\r\n",
    "GET /admin/users?search=%27%%27 HTTP/1.1\r\n\r\n",
    "GET http://192.168.1.96:3000/api/v1/matches/test?1=1 HTTP/1.1\r\n\r\n",
    "GET / HTTP/1.1\r\naaaaaaaaaaaaa:++++++++++\r\n\r\n",
    "GET / SsUTF/1.1",
    "GET /forums/1/topics/2375?page=1#posts-17408 HTTP/1.1\r\n\r\n",
    "GET /forums/1/path;stillpath/2375?page=1 HTTP/1.1\r\n\r\n",
    "GET /path{here HTTP/1.1\r\n\r\n",
    "GET /path\\here HTTP/1.1\r\n\r\n",
    "GET /a|b[c]^d HTTP/1.1\r\n\r\n",
    "GET /search?filter[status]=active&q={a}|b^c`d\\e HTTP/1.1\r\n\r\n",
    "GET http://[::1]:9292/x HTTP/1.1\r\n\r\n",
    "GET / HTTP/1.1\r\nX-Strip-Me: \t Strip This \t      \r\n\r\n",
    "GET / HTTP/1.1\r\nHost: localhost:8080\r\nDummy: x\nDummy2: y\r\n\r\n",
    "GET / HTTP/1.1\r\nHost: localhost:8080\r\nDummy: x\r\nDummy: y\nDummy2: z\r\n\r\n",
    "GET / HTTP/1.1\r\nHost: localhost:8080\r\nDummy: Valid\tValue\r\n\r\n",
    "OPTIONS * HTTP/1.1\r\nHost: h\r\nRequest-Uri: value\r\n\r\n",
    "GET http://h/p HTTP/1.1\r\nHost: h\r\nQuery-String: value\r\n\r\n",
    "QUERY / HTTP/1.1\r\nHost: test.com\r\n\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}",
    "GET /puma/request?query=books&sort=price&order=asc HTTP/1.0\r\n\r\n",
    "a_}{n",
    "\r\n\r\n",
    "\r\n\r\nfoo",
    "GEt /?a=1 HTTP/1.1\r\nHost: test.com\r\n\r\n",
    "GET /\e?a=1 HTTP/1.1\r\nHost: test.com\r\n\r\n",
    "GET /?a=\e1 HTTP/1.1\r\nHost: test.com\r\n\r\n",
    "GET /test?a=1 http/1.1\r\n\r\n",
    "GET /test?a=1 HTTP/1.a\r\n\r\n",
    "GET / HTTP/1.0\r\nHost: \r\n\r\n",
    "GET / HTTP/1.1\r\nHost: test.com\r\nno-return: 10\nContent-Length: 11\r\n\r\nHello World",
    "GET / HTTP/1.1\r\nHost: test.com\r\nno-newline: 10\rContent-Length: 11\r\n\r\nHello World",
    "#{GET_PREFIX}Content_Length: 5\r\nContent-Length: 5\r\n\r\nHello",
    "#{GET_PREFIX}Transfer-Encoding: gzip,chunked\r\n\r\n1\r\nH\r\n4\r\nello\r\n0\r\n\r\n",
    "GET / HTTP/1.1\r\nHost: test.com\r\nConnection: Keep-Alive\r\n\r\nGET /next HTTP/1.1\r\nHost: test.com\r\n\r\n",
    "POST / HTTP/1.1\r\nHost: test.com\r\nContent-Length: 10\r\nExpect: 100-continue\r\n\r\n0123456789",
    "GET /path`here HTTP/1.1\r\nHost: test.com\r\n\r\n",
    "GET / HTTP/1.1\r\nHost: test.com\r\nContent-Length: 5.01\r\n\r\nHello",
    "GET /assets/app.js?v=3 HTTP/1.1\r\nHost: www.example.com\r\n" \
      "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36\r\n" \
      "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8\r\n" \
      "Accept-Language: en-AU,en;q=0.9\r\nAccept-Encoding: gzip, deflate, br, zstd\r\n" \
      "Sec-Ch-Ua: \"Chromium\";v=\"130\", \"Not?A_Brand\";v=\"99\"\r\nSec-Fetch-Site: same-origin\r\n" \
      "Cookie: _session=abc123; theme=dark\r\nCookie: x=1\r\nUpgrade-Insecure-Requests: 1\r\n\r\n",
    "PUT /api/v1/items/42 HTTP/1.1\r\nHost: api.example.com\r\nX_Forwarded_For: 10.0.0.1\r\n" \
      "X-Forwarded-For: 10.0.0.2\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}",
    "GET /caf\xC3\xA9?q=\xFF HTTP/1.1\r\nHost: test.com\r\nX-Bytes: \x80\xFE\r\n\r\n",
  ].map { |s| s.b.freeze }.freeze

  INTERESTING = ["\r", "\n", "\r\n", "\t", " ", ":", "?", "#", "/", "%", "*", "{", "}", "`",
    "\\", "\"", "<", ">", "_", "-", ".", "$", "+", "@", ";", "=", "&", "H", "a", "Z", "0",
    "\x00", "\x01", "\x1f", "\x7f", "\x80", "\xff", "HTTP/1.1", "\r\n\r\n"].map { |s| s.b.freeze }.freeze

  NAME_BYTES = "abcXYZ-_!#$%&'*+.^`|~09".b.bytes.freeze

  # Lengths either side of the parser's limits, for inputs that probe them.
  LIMIT_LENGTHS = [20, 256, 1024, 8192, 10 * 1024, 12 * 1024, 80 * 1024].flat_map { |n| [n - 1, n, n + 1] }.freeze

  module_function

  # Returns nil when both parsers agree on +input+ fed as split at +cuts+,
  # otherwise a description of the first difference.
  def compare(input, cuts = [], encoding: BINARY)
    native = run(Puma::NativeHttpParser, input, cuts, encoding)
    ruby = run(Puma::RubyHttpParser, input, cuts, encoding)
    return nil if native == ruby

    describe(input, cuts, native, ruby)
  end

  # Compares +input+ whole and split into two pieces at each offset. Inputs
  # longer than +every_offset_up_to+ are split at a sample of offsets instead:
  # +sample+ offsets either side of delimiters, and +sample+ random ones. A few
  # random splits into several pieces follow.
  def check(input, rng, every_offset_up_to: 2048, sample: 32, encoding: BINARY)
    len = input.bytesize
    offsets =
      if len <= every_offset_up_to
        (1...len).to_a
      else
        boundaries = []
        input.each_byte.with_index { |b, i| boundaries << i << i + 1 if b == 10 || b == 13 || b == 32 || b == 58 || b == 63 || b == 35 }
        (boundaries.uniq.sample(sample, random: rng) + Array.new(sample) { rng.rand(1...len) })
          .select { |i| i > 0 && i < len }.uniq
      end

    diff = compare(input, encoding: encoding)
    return diff if diff

    offsets.each do |i|
      diff = compare(input, [i], encoding: encoding)
      return diff if diff
    end

    if len > 2
      4.times do
        diff = compare(input, Array.new(rng.rand(2..6)) { rng.rand(1...len) }.sort.uniq, encoding: encoding)
        return diff if diff
      end
    end
    nil
  end

  # One request in each URI form, with a path, query, fragment and headers,
  # for #sweep to edit.
  SWEEP_TEMPLATES = [
    "GET /p/a?q=1#f HTTP/1.1\r\nHost: h\r\nX-A_b: v \tw\r\n\r\nB",
    "GET http://h:1/p?q HTTP/1.0\r\n\r\n",
    "OPTIONS *#f HTTP/1.1\r\n\r\n",
  ].map { |s| s.b.freeze }.freeze

  # Tries every byte value as a replacement for, and an insertion before, each
  # byte of +template+, comparing each result whole and split just after the
  # edited byte. Returns the first difference, or nil.
  def sweep(template)
    template.bytesize.times do |i|
      head = template.byteslice(0, i)
      256.times do |b|
        byte = b.chr.b
        [head + byte + template.byteslice(i + 1..), head + byte + template.byteslice(i..)].each do |input|
          diff = compare(input) || compare(input, [i + 1])
          return diff if diff
        end
      end
    end
    nil
  end

  def run(klass, input, cuts, encoding)
    parser = klass.new
    env = {}
    buf = String.new(capacity: input.bytesize, encoding: encoding)
    snaps = []
    prev = 0
    (cuts + [input.bytesize]).each do |cut|
      next if cut <= prev && !input.empty?
      buf << input.byteslice(prev, cut - prev).force_encoding(encoding)
      prev = cut
      result =
        begin
          parser.execute(env, buf, parser.nread)
        rescue Puma::HttpParserError => e
          [e.class, e.message]
        end
      snaps << snapshot(parser, env, buf, result)
      break if result.is_a?(Array) || parser.finished?
    end
    snaps
  end

  def snapshot(parser, env, buf, result)
    body = parser.body
    {
      result: result,
      env: env.map { |k, v| [k, k.encoding, k.frozen?, v.dup, v.encoding, v.frozen?] },
      finished: parser.finished?,
      error: parser.error?,
      nread: parser.nread,
      body: body && [body.dup, body.encoding],
      buffer: [buf.b, buf.encoding],
    }
  end

  def describe(input, cuts, native, ruby)
    index = native.zip(ruby).index { |a, b| a != b } || [native.size, ruby.size].min
    a = native[index] || {}
    b = ruby[index] || {}
    fields = (a.keys | b.keys).reject { |k| a[k] == b[k] }
    lines = ["input=#{input.inspect[0, 300]} (#{input.bytesize} bytes) cuts=#{cuts.inspect} call=#{index}"]
    fields.each do |f|
      lines << "  #{f}: C    #{a[f].inspect[0, 300]}"
      lines << "  #{f}: Ruby #{b[f].inspect[0, 300]}"
    end
    lines << "  calls: C #{native.size}, Ruby #{ruby.size}" if fields.empty?
    lines.join("\n")
  end

  # Applies one to three random edits to +input+.
  def mutate(input, rng)
    out = input.dup
    rng.rand(1..3).times do
      len = out.bytesize
      pos = len.zero? ? 0 : rng.rand(0..len)
      case rng.rand(10)
      when 0 # overwrite a byte
        out.setbyte(pos, rng.rand(256)) if pos < len
      when 1 # insert an interesting token
        out.insert(pos, INTERESTING.sample(random: rng))
      when 2 # delete a short range
        out[pos, rng.rand(1..8)] = "".b if pos < len
      when 3 # duplicate a short range
        out.insert(pos, out.byteslice(pos, rng.rand(1..16)) || "".b)
      when 4 # splice in part of another seed
        other = SEEDS.sample(random: rng)
        from = rng.rand(0...other.bytesize)
        out.insert(pos, other.byteslice(from, rng.rand(1..40)))
      when 5 # truncate
        out = out.byteslice(0, pos)
      when 6 # break a line ending
        crlf = out.enum_for(:scan, "\r\n").map { Regexp.last_match.begin(0) }
        out[crlf.sample(random: rng), 2] = ["\n", "\r", "\r\r\n", "\n\r"].sample(random: rng).b unless crlf.empty?
      when 7 # add a header with an unusual name
        line_end = out.index("\r\n")
        name = Array.new(rng.rand(1..12)) { NAME_BYTES.sample(random: rng) }.pack("C*")
        value = [" v", "", " \t x \t", "  a, b", " \x80\xff"].sample(random: rng).b
        out.insert(line_end + 2, "#{name}:#{value}\r\n".b) if line_end
      when 8 # flip the case of a letter
        b = out.getbyte(pos)
        out.setbyte(pos, b ^ 0x20) if b && ((65..90).cover?(b) || (97..122).cover?(b))
      when 9 # stretch to a length near one of the limits
        filler = ["a", "/", "%", " ", "\t", "?", "b=c&"].sample(random: rng)
        out.insert(pos, (filler * LIMIT_LENGTHS.sample(random: rng)).byteslice(0, LIMIT_LENGTHS.sample(random: rng)).b)
      end
    end
    out
  end
end
