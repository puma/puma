require "bundler/setup"
require "rake/testtask"
require "rake/extensiontask"
require "rake/javaextensiontask"
require_relative 'lib/puma/detect'
require 'rubygems/package_task'
require 'bundler/gem_tasks'

begin
  # Add rubocop task
  require "rubocop/rake_task"
  RuboCop::RakeTask.new
rescue LoadError
end

gemspec = Gem::Specification.load("puma.gemspec")
Gem::PackageTask.new(gemspec).define

Rake::FileUtilsExt.verbose_flag = !!ENV['PUMA_TEST_DEBUG']
# generate extension code using Ragel (C and Java)
desc "Generate extension code (C and Java) using Ragel"
task :ragel do
  sh "ragel ext/puma_http11/http11_parser.rl -C -G2 -I ext/puma_http11 -o ext/puma_http11/http11_parser.c"
  sh "ragel ext/puma_http11/http11_parser.java.rl -J -G2 -I ext/puma_http11 -o ext/puma_http11/org/jruby/puma/Http11Parser.java"
end

if !Puma.jruby?
  # compile extensions using rake-compiler
  # C (MRI, Rubinius)
  Rake::ExtensionTask.new("puma_http11", gemspec) do |ext|
    # place extension inside namespace
    ext.lib_dir = "lib/puma"

    CLEAN.include "lib/puma/{1.8,1.9}"
    CLEAN.include "lib/puma/puma_http11.rb"
    CLEAN.include "tmp"
  end
else
  # Java (JRuby)
  # ::Rake::JavaExtensionTask.source_files supplies the list of files to
  # compile.  At present, it only works with a glob prefixed with @ext_dir.
  # override it so we can select the files
  class ::Rake::JavaExtensionTask
    def source_files
      if ENV["PUMA_DISABLE_SSL"]
        # uses no_ssl/PumaHttp11Service.java, removes MiniSSL.java
        FileList[
          File.join(@ext_dir, "no_ssl/PumaHttp11Service.java"),
          File.join(@ext_dir, "org/jruby/puma/EnvKey.java"),
          File.join(@ext_dir, "org/jruby/puma/Http11.java"),
          File.join(@ext_dir, "org/jruby/puma/Http11Parser.java")
        ]
      else
        FileList[
          File.join(@ext_dir, "PumaHttp11Service.java"),
          File.join(@ext_dir, "org/jruby/puma/EnvKey.java"),
          File.join(@ext_dir, "org/jruby/puma/Http11.java"),
          File.join(@ext_dir, "org/jruby/puma/Http11Parser.java"),
          File.join(@ext_dir, "org/jruby/puma/MiniSSL.java")
        ]
      end
    end
  end

  Rake::JavaExtensionTask.new("puma_http11", gemspec) do |ext|
    ext.lib_dir = "lib/puma"
    ext.release = '8'
    ext.java_compiling do |spec|
      spec.files = spec.files.reject { |f| f.start_with?("ext/") }
    end
  end
end

# the following is a fat-binary stub that will be used when
# require 'puma/puma_http11' and will use either 1.8 or 1.9 version depending
# on RUBY_VERSION
file "lib/puma/puma_http11.rb" do |t|
  File.open(t.name, "w") do |f|
    f.puts "RUBY_VERSION =~ /(\d+.\d+)/"
    f.puts 'require "puma/#{$1}/puma_http11"'
  end
end

require_relative "test/categories"

# tests require extension be compiled, but depend on the platform
if Puma.jruby?
  test_prereq = :java
else
  task :compile_for_test do
    original_makeflags = ENV["MAKEFLAGS"]
    ENV["MAKEFLAGS"] = [original_makeflags, "-s"].compact.join(" ")
    Rake::Task[:compile].invoke
  ensure
    ENV["MAKEFLAGS"] = original_makeflags
  end

  test_prereq = :compile_for_test
end

# Integration = process-spawn / TestIntegration. Unit = in-process complement.
# See test/categories.rb and CONTRIBUTING.md ("Running tests").
namespace :test do
  Rake::TestTask.new(:unit) do |t|
    t.description = "Run in-process (unit) tests"
    t.test_files = PumaTestCategories.unit_paths
  end

  Rake::TestTask.new(:integration) do |t|
    t.description = "Run process-spawn (integration) tests"
    t.test_files = PumaTestCategories.integration_paths
  end
end

Rake::TestTask.new(:test) do |t|
  t.description = "Run the full test suite"
end

task "test:unit" => test_prereq
task "test:integration" => test_prereq
task :test => test_prereq

task :default => [:rubocop, :test]
