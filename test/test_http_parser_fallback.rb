# frozen_string_literal: true

require_relative "helper"
require "open3"
require "tmpdir"

# Puma falls back to Puma::RubyHttpParser when its C extension can't be
# loaded. The Ruby parser CI jobs only set PUMA_PURE_RUBY_PARSER, which still
# loads the extension, so this test makes the extension fail to load in a
# fresh process and serves a request there.
class TestHttpParserFallback < PumaTest
  SCRIPT = <<~'RUBY'
    require "puma"
    require "socket"

    puts "parser: #{Puma::HttpParser}"
    puts "native parser: #{defined?(Puma::NativeHttpParser) ? "loaded" : "absent"}"
    puts "ssl: #{Puma.ssl?}"
    puts "subreaper: #{Puma.enable_child_subreaper}"

    app = ->(env) { [200, {}, [env["HTTP_X_TEST"].to_s]] }
    server = Puma::Server.new(app, nil, log_writer: Puma::LogWriter.null)
    port = server.add_tcp_listener("127.0.0.1", 0).addr[1]
    server.run
    sock = TCPSocket.new("127.0.0.1", port)
    sock.write "GET / HTTP/1.0\r\nX-Test: parsed in Ruby\r\n\r\n"
    puts "response: #{sock.read.split("\r\n\r\n", 2).last}"
    sock.close
    server.stop(true)
  RUBY

  def setup
    skip_unless :mri
  end

  def test_serves_requests_when_the_extension_fails_to_load
    Dir.mktmpdir do |dir|
      # Found before the real extension, because its directory comes first
      # on the load path.
      Dir.mkdir File.join(dir, "puma")
      File.write File.join(dir, "puma", "puma_http11.rb"),
        %(raise LoadError, "simulated load failure"\n)

      lib = File.expand_path("../lib", __dir__)
      out, err, status = Open3.capture3(Gem.ruby, "-I", dir, "-I", lib, "-e", SCRIPT)
      assert status.success?, "script failed:\n#{out}#{err}"

      assert_equal [
        "parser: Puma::RubyHttpParser",
        "native parser: absent",
        "ssl: false",
        "subreaper: false",
        "response: parsed in Ruby",
      ], out.lines.map(&:chomp)
      assert_match(/WARNING: Puma could not load its C extension \(simulated load failure\)/, err)
    end
  end
end
