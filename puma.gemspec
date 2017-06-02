# -*- encoding: utf-8 -*-

# This is only used when puma is a git dep from Bundler, keep in sync with Rakefile

version = File.read(File.expand_path("../lib/puma/const.rb", __FILE__))[/VERSION = "(\d+\.\d+\.\d+)"/, 1] || raise

Gem::Specification.new do |s|
  s.name = "puma"
  s.version = version
  s.authors = ["Evan Phoenix"]
  s.description = "Puma is a simple, fast, threaded, and highly concurrent HTTP 1.1 server for Ruby/Rack applications. Puma is intended for use in both development and production environments. It's great for highly concurrent Ruby implementations such as Rubinius and JRuby as well as as providing process worker support to support CRuby well."
  s.summary = "Puma is a simple, fast, threaded, and highly concurrent HTTP 1.1 server for Ruby/Rack applications"
  s.email = ["evan@phx.io"]
  s.executables = ["puma", "pumactl"]
  s.extensions = ["ext/puma_http11/extconf.rb"]
  s.files = `git ls-files`.split($/)
  s.homepage = "http://puma.io"
  s.license = "BSD-3-Clause"
  s.required_ruby_version = Gem::Requirement.new(">= 1.9.3")
end
