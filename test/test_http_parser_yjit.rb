# frozen_string_literal: true

require_relative "helper"
require "open3"

# Under YJIT, Puma::RubyHttpParser's compiled code must not be invalidated
# while it serves requests. On Ruby 4.0 and 4.1-dev, code invalidated because
# a constant cache was filled or cleared can be left exiting to the
# interpreter on every call, for the life of the process, which made the
# parser run about twice as slow. Two ordinary events caused that:
#
# * YJIT compiles the parser before any request has a query string, so the
#   constant caches on that path are still empty. The first query string
#   fills them, which invalidates the compiled code.
# * Other code defines a constant that shares a name with one the parser
#   uses, such as SPACE. Since Ruby 3.2 that clears every constant cache for
#   the name, the parser's included.
#
# Whether a given invalidation leaves code stuck in the interpreter depends on
# how YJIT laid the code out, which unrelated edits can change, so this test
# checks for the invalidations themselves rather than timing parses.
class TestHttpParserYJIT < PumaTest
  # The script runs in a fresh process, because the parser's constant caches
  # in this one were filled by other tests.
  SCRIPT = <<~'RUBY'
    require "puma"

    def invalidations
      RubyVM::YJIT.runtime_stats[:invalidation_count]
    end

    unless (RubyVM::YJIT.runtime_stats || {}).key?(:invalidation_count)
      puts "skip: this Ruby's YJIT does not report invalidation_count"
      exit
    end

    MINIMAL = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
    QUERY = "GET /search?q=puma HTTP/1.1\r\nHost: localhost\r\nAccept-Language: en\r\n\r\n"

    # One parser, reset for each request, as on a keep-alive connection.
    # Creating a parser is left out: it happens once per connection, and
    # #initialize reads constants on purpose.
    $parser = Puma::RubyHttpParser.new

    def parse(request)
      $parser.reset
      $parser.execute({}, request.b, 0)
      raise "did not finish parsing" unless $parser.finished?
    end

    # Health checks first, so YJIT compiles the parser before it sees a query
    # string.
    100.times { parse(MINIMAL) }
    before = invalidations
    100.times { parse(QUERY) }
    puts "first query strings: #{invalidations - before}"

    # Then constants named like the parser's own, and like the others it
    # uses, defined somewhere else.
    names = Puma::RubyHttpParser.constants(false).sort + %i[Encoding BINARY StringScanner]
    names.each do |name|
      before = invalidations
      Module.new.const_set(name, nil)
      50.times { parse(MINIMAL); parse(QUERY) }
      n = invalidations - before
      puts "#{name}: #{n}" if n > 0
    end
    puts "done"
  RUBY

  def setup
    skip_unless :mri
    skip "needs YJIT" unless defined?(RubyVM::YJIT)
  end

  def test_parsing_does_not_invalidate_yjit_code
    lib = File.expand_path("../lib", __dir__)
    out, err, status = Open3.capture3(Gem.ruby, "--yjit", "--yjit-call-threshold=30", "-I", lib, "-e", SCRIPT)
    assert status.success?, "script failed:\n#{out}#{err}"
    skip out.strip if out.start_with?("skip:")
    assert_equal "done", out.lines.last&.chomp, out

    report = out.lines[0...-1].map(&:chomp)
    assert_equal ["first query strings: 0"], report,
      "YJIT invalidated compiled parser code (invalidations per event):\n#{report.join("\n")}"
  end
end
