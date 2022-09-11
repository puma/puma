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
task :ragel

file 'ext/puma_http11/http11_parser.c' => ['ext/puma_http11/http11_parser.rl'] do |t|
  begin
    sh "ragel #{t.prerequisites.last} -C -G2 -I ext/puma_http11 -o #{t.name}"
  rescue
    fail "Could not build wrapper using Ragel (it failed or not installed?)"
  end
end
task :ragel => ['ext/puma_http11/http11_parser.c']

file 'ext/puma_http11/org/jruby/puma/Http11Parser.java' => ['ext/puma_http11/http11_parser.java.rl'] do |t|
  begin
    sh "ragel #{t.prerequisites.last} -J -G2 -I ext/puma_http11 -o #{t.name}"
  rescue
    fail "Could not build wrapper using Ragel (it failed or not installed?)"
  end
end
task :ragel => ['ext/puma_http11/org/jruby/puma/Http11Parser.java']

if !Puma.jruby?
  # compile extensions using rake-compiler
  # C (MRI, Rubinius)
  Rake::ExtensionTask.new("puma_http11", gemspec) do |ext|
    # place extension inside namespace
    ext.lib_dir = "lib/puma"

    CLEAN.include "lib/puma/{1.8,1.9}"
    CLEAN.include "lib/puma/puma_http11.rb"
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
          File.join(@ext_dir, "org/jruby/puma/Http11.java"),
          File.join(@ext_dir, "org/jruby/puma/Http11Parser.java")
        ]
      else
        FileList[
          File.join(@ext_dir, "PumaHttp11Service.java"),
          File.join(@ext_dir, "org/jruby/puma/Http11.java"),
          File.join(@ext_dir, "org/jruby/puma/Http11Parser.java"),
          File.join(@ext_dir, "org/jruby/puma/MiniSSL.java")
        ]
      end
    end
  end

  Rake::JavaExtensionTask.new("puma_http11", gemspec) do |ext|
    ext.lib_dir = "lib/puma"
    ext.source_version = '1.8'
    ext.target_version = '1.8'
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

Rake::TestTask.new(:test)

# tests require extension be compiled, but depend on the platform
if Puma.jruby?
  task :test => [:java]
else
  task :test => [:compile]
end

namespace :test do
  desc "Run all tests"

  task :all => :test
end

task :default => [:rubocop, "test:all"]
