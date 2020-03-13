require "bundler/setup"
require "rake/testtask"
require "rake/extensiontask"
require "rake/javaextensiontask"
require "rubocop/rake_task"
require_relative 'lib/puma/detect'
require 'rubygems/package_task'
require 'bundler/gem_tasks'
require "uri"
require 'net/http'

gemspec = Gem::Specification.load("puma.gemspec")
Gem::PackageTask.new(gemspec).define

# Add rubocop task
RuboCop::RakeTask.new

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
  task :java => :maven_dependencies
  # create a task which will download the dependencies if they do not exist already in the working directory
  task :maven_dependencies do
    %w(https://repo1.maven.org/maven2/io/netty/netty-common/4.1.47.Final/netty-common-4.1.47.Final.jar
       https://repo1.maven.org/maven2/io/netty/netty-codec/4.1.47.Final/netty-codec-4.1.47.Final.jar
       https://repo1.maven.org/maven2/io/netty/netty-buffer/4.1.47.Final/netty-buffer-4.1.47.Final.jar
       https://repo1.maven.org/maven2/io/netty/netty-handler/4.1.47.Final/netty-handler-4.1.47.Final.jar
       https://repo1.maven.org/maven2/io/netty/netty-tcnative-boringssl-static/2.0.29.Final/netty-tcnative-boringssl-static-2.0.29.Final.jar).each do |dependency|
      filename = URI(dependency).path.split('/').last
      next if File.exists?(filename)
      puts URI(dependency)
      response = Net::HTTP.get_response(URI(dependency))
      open(filename, "wb") { |file|
        file.write(response.body)
      }
    end
  end

    # Java (JRuby)
  Rake::JavaExtensionTask.new("puma_http11", gemspec) do |ext|
    ext.lib_dir = "lib/puma"
    ext.classpath = "netty-handler-4.1.47.Final.jar:netty-buffer-4.1.47.Final.jar"
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

Rake::TestTask.new(:test) do |t|
  t.ruby_opts = ["-J-Djava.util.logging.config.file=logging.properties -J-Dpuma.ssl.use-netty=true"]
end

# tests require extension be compiled, but depend on the platform
if Puma.jruby?
  task :test => [:java]
else
  task :test => [:compile]
end

namespace :test do
  desc "Run the integration tests"
  
  task :integration do
    sh "ruby test/shell/run.rb"
  end

  desc "Run all tests"
  if (Puma.jruby? && ENV['TRAVIS']) || Puma.windows?
    task :all => :test
  else
    task :all => [:test, "test:integration"]
  end
end

task :default => [:rubocop, "test:all"]
