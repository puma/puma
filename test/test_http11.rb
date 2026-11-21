# frozen_string_literal: true

# Copyright (c) 2011 Evan Phoenix
# Copyright (c) 2005 Zed A. Shaw

require_relative "helper"
require_relative "helpers/integration"
require "digest"

# Runs against the extension's parser. Http11RubyParserTest below runs the
# same tests against Puma::RubyHttpParser.
class Http11ParserTest < TestIntegration

  parallelize_me! unless ::Puma::IS_JRUBY && RUBY_DESCRIPTION.include?('x86_64-darwin')

  def setup
    skip "needs the puma_http11 extension" unless parser_class
    super
  end

  def parser_class
    Puma::NativeHttpParser if defined?(Puma::NativeHttpParser)
  end

  def test_parse_simple
    parser = parser_class.new
    req = {}
    http = "GET /?a=1 HTTP/1.1\r\n\r\n"
    nread = parser.execute(req, http, 0)

    assert nread == http.length, "Failed to parse the full HTTP request"
    assert parser.finished?, "Parser didn't finish"
    assert !parser.error?, "Parser had error"
    assert nread == parser.nread, "Number read returned from execute does not match"

    assert_equal '/', req['REQUEST_PATH']
    assert_equal 'HTTP/1.1', req['SERVER_PROTOCOL']
    assert_equal '/?a=1', req['REQUEST_URI']
    assert_equal 'GET', req['REQUEST_METHOD']
    assert_nil req['FRAGMENT']
    assert_equal "a=1", req['QUERY_STRING']

    parser.reset
    assert parser.nread == 0, "Number read after reset should be 0"
  end

  def test_parse_escaping_in_query
    parser = parser_class.new
    req = {}
    http = "GET /admin/users?search=%27%%27 HTTP/1.1\r\n\r\n"
    nread = parser.execute(req, http, 0)

    assert nread == http.length, "Failed to parse the full HTTP request"
    assert parser.finished?, "Parser didn't finish"
    assert !parser.error?, "Parser had error"
    assert nread == parser.nread, "Number read returned from execute does not match"

    assert_equal '/admin/users?search=%27%%27', req['REQUEST_URI']
    assert_equal "search=%27%%27", req['QUERY_STRING']

    parser.reset
    assert parser.nread == 0, "Number read after reset should be 0"
  end

  def test_parse_absolute_uri
    parser = parser_class.new
    req = {}
    http = "GET http://192.168.1.96:3000/api/v1/matches/test?1=1 HTTP/1.1\r\n\r\n"
    nread = parser.execute(req, http, 0)

    assert nread == http.length, "Failed to parse the full HTTP request"
    assert parser.finished?, "Parser didn't finish"
    assert !parser.error?, "Parser had error"
    assert nread == parser.nread, "Number read returned from execute does not match"

    assert_equal "GET", req['REQUEST_METHOD']
    assert_equal 'http://192.168.1.96:3000/api/v1/matches/test?1=1', req['REQUEST_URI']
    assert_equal 'HTTP/1.1', req['SERVER_PROTOCOL']

    assert_nil req['REQUEST_PATH']
    assert_nil req['FRAGMENT']
    assert_nil req['QUERY_STRING']

    parser.reset
    assert parser.nread == 0, "Number read after reset should be 0"

  end

  def test_parse_dumbfuck_headers
    parser = parser_class.new
    req = {}
    should_be_good = "GET / HTTP/1.1\r\naaaaaaaaaaaaa:++++++++++\r\n\r\n"
    nread = parser.execute(req, should_be_good, 0)
    assert_equal should_be_good.length, nread
    assert parser.finished?
    assert !parser.error?
  end

  def test_parse_error
    parser = parser_class.new
    req = {}
    bad_http = "GET / SsUTF/1.1"

    error = false
    begin
      parser.execute(req, bad_http, 0)
    rescue
      error = true
    end

    assert error, "failed to throw exception"
    assert !parser.finished?, "Parser shouldn't be finished"
    assert parser.error?, "Parser SHOULD have error"
  end

  def test_fragment_in_uri
    parser = parser_class.new
    req = {}
    get = "GET /forums/1/topics/2375?page=1#posts-17408 HTTP/1.1\r\n\r\n"

    parser.execute(req, get, 0)

    assert parser.finished?
    assert_equal '/forums/1/topics/2375?page=1', req['REQUEST_URI']
    assert_equal 'posts-17408', req['FRAGMENT']
  end

  def test_semicolon_in_path
    parser = parser_class.new
    req = {}
    get = "GET /forums/1/path;stillpath/2375?page=1 HTTP/1.1\r\n\r\n"

    parser.execute(req, get, 0)

    assert parser.finished?
    assert_equal '/forums/1/path;stillpath/2375?page=1', req['REQUEST_URI']
    assert_equal '/forums/1/path;stillpath/2375', req['REQUEST_PATH']
  end

  REJECTED_PATH_CHARS = ['{', '}', '`', '\\']

  def test_rejects_unescaped_characters_in_path
    parser = parser_class.new

    REJECTED_PATH_CHARS.each do |char|
      get = "GET /path#{char}here HTTP/1.1\r\n\r\n"

      assert_raises(Puma::HttpParserError, "expected #{char.inspect} in path to be rejected") do
        parser.execute({}, get, 0)
      end
      parser.reset
    end
  end

  def test_accepts_browser_unescaped_characters_in_path
    parser = parser_class.new
    req = {}
    parser.execute(req, "GET /a|b[c]^d HTTP/1.1\r\n\r\n", 0)

    assert parser.finished?
    assert_equal '/a|b[c]^d', req['REQUEST_PATH']
  end

  def test_accepts_browser_unescaped_characters_in_query
    parser = parser_class.new
    req = {}
    parser.execute(req, "GET /search?filter[status]=active&q={a}|b^c`d\\e HTTP/1.1\r\n\r\n", 0)

    assert parser.finished?
    assert_equal 'filter[status]=active&q={a}|b^c`d\\e', req['QUERY_STRING']
  end

  def test_parse_absolute_uri_with_ipv6_literal
    parser = parser_class.new
    req = {}
    http = "GET http://[::1]:9292/x HTTP/1.1\r\n\r\n"
    nread = parser.execute(req, http, 0)

    assert_equal http.length, nread
    assert parser.finished?
    refute parser.error?
    assert_equal 'http://[::1]:9292/x', req['REQUEST_URI']
  end

  # lame random garbage maker
  def rand_data(min, max, readable=true)
    count = min + ((rand(max)+1) *10).to_i
    res = count.to_s + "/"

    if readable
      res << Digest(:SHA1).hexdigest(rand(count * 100).to_s) * (count / 40)
    else
      data = Digest(:SHA1).digest(rand(count * 100).to_s) * (count / 20)
      # Guarantee there is an invalid byte at the end of the string
      data.setbyte(data.bytesize - 1, 0x1)
      res << data
    end

    res
  end

  def test_get_const_length
    skip_unless :jruby

    envs = %w[
      PUMA_REQUEST_URI_MAX_LENGTH
      PUMA_REQUEST_PATH_MAX_LENGTH
      PUMA_QUERY_STRING_MAX_LENGTH
    ]
    default_exp = [1024 * 12, 8192, 10 * 1024]
    tests = [{ envs: %w[60000 61000 62000], exp: [60000, 61000, 62000], error_indexes: [] },
             { envs: ['', 'abc', nil], exp: default_exp, error_indexes: [1] },
             { envs: %w[-4000 0 3000.45], exp: default_exp, error_indexes: [0, 1, 2] }]
    cli_config = <<~CONFIG
        app do |_|
          [200, {}, [JSONSerialization.generate({
                       MAX_REQUEST_URI_LENGTH:      org.jruby.puma.Http11::MAX_REQUEST_URI_LENGTH,
                       MAX_REQUEST_PATH_LENGTH:     org.jruby.puma.Http11::MAX_REQUEST_PATH_LENGTH,
                       MAX_QUERY_STRING_LENGTH:     org.jruby.puma.Http11::MAX_QUERY_STRING_LENGTH,
                       MAX_REQUEST_URI_LENGTH_ERR:  org.jruby.puma.Http11::MAX_REQUEST_URI_LENGTH_ERR,
                       MAX_REQUEST_PATH_LENGTH_ERR: org.jruby.puma.Http11::MAX_REQUEST_PATH_LENGTH_ERR,
                       MAX_QUERY_STRING_LENGTH_ERR: org.jruby.puma.Http11::MAX_QUERY_STRING_LENGTH_ERR })]]
        end
    CONFIG

    tests.each do |conf|
      cli_server 'test/rackup/hello.ru',
        env: {envs[0]  => conf[:envs][0], envs[1] => conf[:envs][1], envs[2] => conf[:envs][2]},
        merge_err: true,
        config: cli_config

      sleep 0.25
      result = JSON.parse read_body(connect)

      assert_equal conf[:exp][0], result['MAX_REQUEST_URI_LENGTH']
      assert_equal conf[:exp][1], result['MAX_REQUEST_PATH_LENGTH']
      assert_equal conf[:exp][2], result['MAX_QUERY_STRING_LENGTH']

      assert_includes result['MAX_REQUEST_URI_LENGTH_ERR'], "longer than the #{conf[:exp][0]} allowed length"
      assert_includes result['MAX_REQUEST_PATH_LENGTH_ERR'], "longer than the #{conf[:exp][1]} allowed length"
      assert_includes result['MAX_QUERY_STRING_LENGTH_ERR'], "longer than the #{conf[:exp][2]} allowed length"

      conf[:error_indexes].each do |index|
        assert_includes @server_log, "The value #{conf[:envs][index]} for #{envs[index]} is invalid. "\
          "Using default value #{default_exp[index]} instead"
      end

      stop_server
     end
  end

  def test_max_uri_path_length
    parser = parser_class.new
    req = {}

    # Support URI path length to a max of 8192
    path = "/" + rand_data(7000, 100)
    http = "GET #{path} HTTP/1.1\r\n\r\n"
    parser.execute(req, http, 0)
    assert_equal path, req['REQUEST_PATH']
    parser.reset

    # Raise exception if URI path length > 8192
    path = "/" + rand_data(9000, 100)
    http = "GET #{path} HTTP/1.1\r\n\r\n"
    assert_raises Puma::HttpParserError do
      parser.execute(req, http, 0)
    end
    parser.reset
  end

  def test_horrible_queries
    parser = parser_class.new

    # then that large header names are caught
    10.times do |c|
      get = "GET /#{rand_data(10,120)} HTTP/1.1\r\nX-#{rand_data(1024, 1024+(c*1024))}: Test\r\n\r\n"
      assert_raises Puma::HttpParserError do
        parser.execute({}, get, 0)
      end
      parser.reset
    end

    # then that large mangled field values are caught
    10.times do |c|
      get = "GET /#{rand_data(10,120)} HTTP/1.1\r\nX-Test: #{rand_data(1024, 1024+(c*1024), false)}\r\n\r\n"
      assert_raises Puma::HttpParserError do
        parser.execute({}, get, 0)
      end
      parser.reset
    end

    # then large headers are rejected too
    mult = TRUFFLE ? 10 : 80
    get = "GET /#{rand_data(10,120)} HTTP/1.1\r\n" \
      "#{"X-Test: test\r\n" * (mult * 1024)}"
    assert_raises Puma::HttpParserError do
      parser.execute({}, get, 0)
    end
    parser.reset

    # finally just that random garbage gets blocked all the time
    10.times do |c|
      get = "GET #{rand_data(1024, 1024+(c*1024), false)} #{rand_data(1024, 1024+(c*1024), false)}\r\n\r\n"
      assert_raises Puma::HttpParserError do
        parser.execute({}, get, 0)
      end
      parser.reset
    end
  end

  def test_trims_whitespace_from_headers
    parser = parser_class.new
    req = {}
    # The C parser upcases header names in the buffer it is given, even a
    # frozen one, and writes through to any string that shares the buffer's
    # bytes. Before Ruby 3.2, +request (a copy) shares a long literal's bytes,
    # and both parser test classes run this method with the same literal. So
    # the buffer gets bytes of its own.
    request = "GET / HTTP/1.1\r\nX-Strip-Me: \t Strip This \t      \r\n\r\n"
    http = String.new(capacity: request.bytesize) << request

    parser.execute(req, http, 0)

    assert_equal "Strip This", req["HTTP_X_STRIP_ME"]
  end

  def test_newline_smuggler
    parser = parser_class.new
    req = {}
    http = "GET / HTTP/1.1\r\nHost: localhost:8080\r\nDummy: x\nDummy2: y\r\n\r\n"

    parser.execute(req, http, 0) rescue nil # We test the raise elsewhere.

    assert parser.error?, "Parser SHOULD have error"
  end

  def test_newline_smuggler_two
    parser = parser_class.new
    req = {}
    http = "GET / HTTP/1.1\r\nHost: localhost:8080\r\nDummy: x\r\nDummy: y\nDummy2: z\r\n\r\n"

    parser.execute(req, http, 0) rescue nil

    assert parser.error?, "Parser SHOULD have error"
  end

  def test_htab_in_header_val
    parser = parser_class.new
    req = {}
    http = "GET / HTTP/1.1\r\nHost: localhost:8080\r\nDummy: Valid\tValue\r\n\r\n"

    parser.execute(req, http, 0)

    assert_equal "Valid\tValue", req['HTTP_DUMMY']
  end

  def test_request_line_key_named_headers_are_http_prefixed
    keys = %w[QUERY_STRING REQUEST_PATH REQUEST_URI REQUEST_METHOD SERVER_PROTOCOL FRAGMENT]

    ['GET /p', 'GET /p?a=1', 'GET http://h/p', 'OPTIONS *'].each do |line|
      expected = {}
      parser_class.new.execute(expected, "#{line} HTTP/1.1\r\nHost: h\r\n\r\n", 0)

      keys.each do |key|
        name = key.split('_').map(&:capitalize).join('-')
        req = {}
        parser_class.new.execute(req, "#{line} HTTP/1.1\r\nHost: h\r\n#{name}: value\r\n\r\n", 0)

        assert_equal expected.slice(*keys), req.slice(*keys), "#{line} with #{name} header"
        assert_equal 'value', req["HTTP_#{key}"], "#{line} with #{name} header"
      end
    end
  end
end

class Http11RubyParserTest < Http11ParserTest
  def parser_class
    Puma::RubyHttpParser
  end

  # Checks the JRuby extension's constants, not the parser under test.
  undef_method :test_get_const_length

  # The C parser's sources that Puma::RubyHttpParser transcribes: the
  # grammar, its actions, and the limits, messages and env keys.
  C_PARSER_SOURCES = %w[http11_parser_common.rl http11_parser.rl puma_http11.c].freeze
  C_PARSER_SOURCES_DIGEST = "9ce4aa83cc484a430fc99d84eab4fbb41522b83614b7e4bf148b279d6c82c47b"

  # Fails whenever those sources change, so that a change to the C parser
  # isn't left out of the Ruby one. The C and Java parsers drifted apart
  # that way (#1978); the differential fuzzer would catch drift only by chance.
  def test_c_parser_sources_unchanged
    dir = File.expand_path "../ext/puma_http11", __dir__
    sources = C_PARSER_SOURCES.map { |f| File.binread(File.join(dir, f)).gsub("\r\n", "\n") }
    digest = Digest::SHA256.hexdigest sources.join("\0")

    assert_equal C_PARSER_SOURCES_DIGEST, digest, <<~MSG
      The C parser's sources changed (#{C_PARSER_SOURCES.join(", ")} in ext/puma_http11).
      Make the same change in lib/puma/ruby_http_parser.rb, or confirm it needs none,
      then set C_PARSER_SOURCES_DIGEST in #{__FILE__} to the new digest.
    MSG
  end
end
