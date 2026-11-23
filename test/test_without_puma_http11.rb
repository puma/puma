# frozen_string_literal: true

require_relative "helper"
require "open3"

# Runs Puma in a subprocess with its puma_http11 extension hidden,
# as if it could not be built, to check what still works without it.
class TestWithoutPumaHttp11 < PumaTest
  LIB = File.expand_path "../lib", __dir__
  HIDE_EXTENSION = File.expand_path "without_puma_http11", __dir__

  # Standard error is kept apart from the output, since the subprocess can
  # write warnings there that have nothing to do with Puma, such as git
  # refusing to list files for the gemspec that Bundler loads.
  def run_without_extension(code)
    command = [RbConfig.ruby, "-I#{HIDE_EXTENSION}", "-I#{LIB}", "-e", code]
    Open3.capture3(*command)
  end

  def test_puma_loads
    output, errors, status = run_without_extension <<~RUBY
      require "puma"
      require "puma/server"
      puts Puma::HttpParserError.superclass
      puts Puma.ssl?
    RUBY

    assert status.success?, errors
    assert_equal "StandardError\nfalse\n", output
  end

  def test_server_explains_that_it_needs_an_http_parser
    output, errors, status = run_without_extension <<~RUBY
      require "puma"
      require "puma/server"
      begin
        Puma::Server.new(->(_env) { [200, {}, []] }, nil, {})
      rescue LoadError => e
        puts e.message
      end
    RUBY

    assert status.success?, errors
    assert_includes output, "puma_http11 extension could not be loaded"
    assert_includes output, "http_parser"
  end

  def test_server_accepts_an_http_parser
    output, errors, status = run_without_extension <<~RUBY
      require "puma"
      require "puma/server"
      parser_class = Class.new
      server = Puma::Server.new(->(_env) { [200, {}, []] }, nil, { http_parser: parser_class })
      puts server.instance_variable_get(:@http_parser) == parser_class
    RUBY

    assert status.success?, errors
    assert_equal "true\n", output
  end
end
