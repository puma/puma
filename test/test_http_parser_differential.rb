# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/http_parser_fuzzer"

# Checks that Puma::RubyHttpParser behaves exactly like the C extension's
# parser, using the differential fuzzer in helpers/http_parser_fuzzer.rb.
#
# The mutation test is seeded from Minitest's --seed. Set FUZZ_SEED to replay
# a failure and FUZZ_ITERATIONS for a longer run.
class TestHttpParserDifferential < PumaTest
  parallelize_me!

  Fuzz = HttpParserFuzzer

  def setup
    skip_if :jruby, suffix: " (the Java parser's error messages differ from the C parser's)"
    skip "needs the puma_http11 C extension" unless defined?(Puma::NativeHttpParser)
  end

  def test_seeds_split_at_every_offset
    rng = Random.new(1)
    Fuzz::SEEDS.each do |seed|
      diff = Fuzz.check(seed, rng)
      assert_nil diff, diff
    end
  end

  def test_seeds_in_utf8_buffers
    rng = Random.new(2)
    Fuzz::SEEDS.each do |seed|
      diff = Fuzz.check(seed, rng, encoding: Encoding::UTF_8)
      assert_nil diff, diff
    end
  end

  def test_every_byte_in_every_element
    Fuzz::SWEEP_TEMPLATES.each do |template|
      diff = Fuzz.sweep(template)
      assert_nil diff, diff
    end
  end

  def test_length_limit_boundaries
    rng = Random.new(3)
    limit_requests.each do |request|
      diff = Fuzz.check(request.b, rng, every_offset_up_to: 0, sample: 8)
      assert_nil diff, diff
    end
  end

  def test_mutations
    seed = Integer(ENV.fetch("FUZZ_SEED") { Minitest.seed })
    iterations = Integer(ENV.fetch("FUZZ_ITERATIONS", "150"))
    rng = Random.new(seed)

    iterations.times do |i|
      input = Fuzz.mutate(Fuzz::SEEDS.sample(random: rng), rng)
      diff = Fuzz.check(input, rng)
      assert_nil diff, "FUZZ_SEED=#{seed}, iteration #{i}\n#{diff}"
    end
  end

  private

  # Requests whose elements sit just under, at, and just over each limit.
  def limit_requests
    requests = []
    [19, 20, 21].each { |n| requests << "#{'G' * n} / HTTP/1.1\r\n\r\n" }
    [8191, 8192, 8193].each { |n| requests << "GET /#{'a' * (n - 1)} HTTP/1.1\r\n\r\n" }
    [10239, 10240, 10241].each { |n| requests << "GET /?#{'q' * n} HTTP/1.1\r\n\r\n" }
    # REQUEST_URI of n bytes, with the path and query each under their limits
    [12287, 12288, 12289].each { |n| requests << "GET /#{'a' * 5999}?#{'q' * (n - 6001)} HTTP/1.1\r\n\r\n" }
    [1023, 1024, 1025].each { |n| requests << "GET /x##{'f' * n} HTTP/1.1\r\n\r\n" }
    [255, 256, 257].each { |n| requests << "GET / HTTP/1.1\r\n#{'n' * n}: v\r\n\r\n" }
    [81919, 81920, 81921].each do |n|
      requests << "GET / HTTP/1.1\r\nX: #{'v' * n}\r\n\r\n"
      requests << "GET / HTTP/1.1\r\nX:   \t#{'v' * (n - 1)}\r\n\r\n"
      requests << "GET / HTTP/1.1\r\nX: #{'v' * (n - 2)}  \r\n\r\n"
      requests << "GET / HTTP/1.1\r\nX:#{' ' * n}\r\n\r\n"
    end
    # a whole header block of n bytes
    [114687, 114688, 114689].each do |n|
      second = n - 18 - 60_007 - 7
      requests << "GET / HTTP/1.1\r\nX-A: #{'a' * 60_000}\r\nX-B: #{'b' * second}\r\n\r\nbody"
    end
    # the header limit tripping inside a value that never ends
    requests << "GET / HTTP/1.1\r\nX: #{'v' * 120_000}"
    requests << "GET /#{'p' * 120_000}"
    requests
  end
end
