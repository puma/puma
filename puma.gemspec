require_relative "lib/puma/const"

Gem::Specification.new do |s|
  s.name = "puma"
  s.version = Puma::Const::PUMA_VERSION
  s.authors = ["Evan Phoenix"]
  s.description = "Puma is a simple, fast, threaded, and highly parallel HTTP 1.1 server for Ruby/Rack applications. Puma is intended for use in both development and production environments. It's great for highly parallel Ruby implementations such as Rubinius and JRuby as well as as providing process worker support to support CRuby well."
  s.summary = "Puma is a simple, fast, threaded, and highly parallel HTTP 1.1 server for Ruby/Rack applications"
  s.email = ["evan@phx.io"]
  s.executables = ["puma", "pumactl"]
  s.extensions = ["ext/puma_http11/extconf.rb"]
  s.add_runtime_dependency "nio4r", "~> 2.0"
  if RbConfig::CONFIG['ruby_version'] >= '2.5'
    s.metadata["msys2_mingw_dependencies"] = "openssl"
  end
  s.files = `git ls-files -- bin docs ext lib tools`.split("\n") +
            %w[History.md LICENSE README.md]
  s.homepage = "https://puma.io"

  if s.respond_to?(:metadata=)
    s.metadata = {
      "bug_tracker_uri" => "https://github.com/puma/puma/issues",
      "changelog_uri" => "https://github.com/puma/puma/blob/master/History.md",
      "homepage_uri" => "https://puma.io",
      "source_code_uri" => "https://github.com/puma/puma"
    }
  end

  s.license = "BSD-3-Clause"
  s.required_ruby_version = Gem::Requirement.new(">= 2.2")
end
