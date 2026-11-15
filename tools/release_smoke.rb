# frozen_string_literal: true

require "bundler"
require "rubygems/package"
require "tmpdir"
require "open3"

module PumaReleaseSmoke
  module_function

  def run(*command)
    output, error, status = Open3.capture3(*command)
    raise "Archive consumer failed: #{error}\n#{output}" unless status.success?

    output
  end

  def call(path = nil)
    platform = RUBY_ENGINE == "jruby" ? "java" : "ruby"
    if path.to_s.empty?
      paths = Dir["pkg/release/#{platform}/puma-*.gem"]
      raise "Expected exactly one #{platform} archive" unless paths.one?

      path = paths.first
    end
    path = File.expand_path(path)
    spec = Gem::Package.new(path).spec
    raise "Archive does not match consumer runtime" unless spec.name == "puma" && spec.platform.to_s == platform

    Dir.mktmpdir("puma-release-consumer-") do |directory|
      directory = File.realpath(directory)
      dependency_paths = Gem.path
      Bundler.with_unbundled_env do
        run(Gem.ruby, "-S", "gem", "install", path, "--local", "--ignore-dependencies", "--no-document", "--install-dir", directory)
        env = { "GEM_HOME" => directory, "GEM_PATH" => ([directory] + dependency_paths).join(File::PATH_SEPARATOR) }
        Dir.chdir(directory) do
          script = <<~RUBY
            gem "puma", #{spec.version.to_s.inspect}
            require "puma"
            root = #{directory.inspect} + "/"
            abort "Wrong Puma installation" unless File.realpath(Gem.loaded_specs.fetch("puma").full_gem_path).start_with?(root)
            source = $LOADED_FEATURES.find { |file| file.end_with?("/puma.rb") }
            abort "Puma loaded from the source checkout" unless source && File.realpath(source).start_with?(root)
            parser = Puma::HttpParser.new
            parser.execute({}, "GET / HTTP/1.1\\r\\nHost: localhost\\r\\n\\r\\n", 0)
            abort "Parser failed" unless parser.finished?
            Puma::MiniSSL::Context.new
          RUBY
          run(env, Gem.ruby, "-e", script)
          puts run(env, Gem.ruby, File.join(directory, "bin/puma"), "--version")
        end
      end
    end
  end
end

PumaReleaseSmoke.call(ARGV.first) if $PROGRAM_NAME == __FILE__
