require "hoe"
require "rake/extensiontask"
require "rake/javaextensiontask"

HOE = Hoe.spec "puma" do
  self.rubyforge_name = 'puma'
  self.readme_file    = "README.md"

  developer 'Evan Phoenix', 'evan@phx.io'

  spec_extras[:extensions]  = ["ext/puma_http11/extconf.rb"]
  spec_extras[:executables] = ['puma', 'pumactl']

  dependency "rack", "~> 1.2"

  extra_dev_deps << ["rake-compiler", "~> 0.8.0"]
end

# puma.gemspec

file "#{HOE.spec.name}.gemspec" => ['Rakefile'] do |t|
  puts "Generating #{t.name}"
  File.open(t.name, 'wb') { |f| f.write HOE.spec.to_ruby }
end

desc "Generate or update the standalone gemspec file for the project"
task :gemspec => ["#{HOE.spec.name}.gemspec"]

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

# compile extensions using rake-compiler
# C (MRI, Rubinius)
Rake::ExtensionTask.new("puma_http11", HOE.spec) do |ext|
end

# Java (JRuby)
Rake::JavaExtensionTask.new("puma_http11", HOE.spec) do |ext|
end

# tests require extension be compiled
task :test => [:compile]

__END__
require 'rubygems'

require 'hoe'

IS_JRUBY = defined?(RUBY_ENGINE) ? RUBY_ENGINE == "jruby" : false

HOE = Hoe.spec 'puma' do
  self.rubyforge_name = 'puma'
  self.readme_file = "README.md"
  developer 'Evan Phoenix', 'evan@phx.io'

  spec_extras[:extensions] = ["ext/puma_http11/extconf.rb"]
  spec_extras[:executables] = ['puma', 'pumactl']

  dependency 'rack', '~> 1.2'

  extra_dev_deps << ['rake-compiler', "~> 0.7.0"]

  clean_globs.push('test_*.log', 'log')
end

task :test => [:compile]

# hoe/test and rake-compiler don't seem to play well together, so disable
# hoe/test's .gemtest touch file thingy for now
HOE.spec.files -= [".gemtest"]

file "#{HOE.spec.name}.gemspec" => ['Rakefile'] do |t|
  puts "Generating #{t.name}"
  File.open(t.name, 'w') { |f| f.puts HOE.spec.to_ruby }
end

desc "Generate or update the standalone gemspec file for the project"
task :gemspec => ["#{HOE.spec.name}.gemspec"]

# the following tasks ease the build of C file from Ragel one

file 'ext/puma_http11/http11_parser.c' => ['ext/puma_http11/http11_parser.rl'] do |t|
  begin
    sh "ragel #{t.prerequisites.last} -C -G2 -o #{t.name}"
  rescue
    fail "Could not build wrapper using Ragel (it failed or not installed?)"
  end
end

file 'ext/puma_http11/org/jruby/puma/Http11Parser.java' => ['ext/puma_http11/http11_parser.java.rl'] do |t|
  begin
    sh "ragel #{t.prerequisites.last} -J -G2 -o #{t.name}"
  rescue
    fail "Could not build wrapper using Ragel (it failed or not installed?)"
  end
end

if IS_JRUBY
  require 'rake/javaextensiontask'

  # build http11 java extension
  Rake::JavaExtensionTask.new('puma_http11', HOE.spec)

  task :ragel => 'ext/puma_http11/org/jruby/puma/Http11Parser.java'
else
  # use rake-compiler for building the extension
  require 'rake/extensiontask'
  
  # build http11 C extension
  Rake::ExtensionTask.new('puma_http11', HOE.spec) do |ext|
    # define target for extension (supporting fat binaries)
    if RUBY_PLATFORM =~ /mingw|mswin/ then
      RUBY_VERSION =~ /(\d+\.\d+)/
      ext.lib_dir = "lib/#{$1}"
    elsif ENV['CROSS']
      # define cross-compilation tasks when not on Windows.
      ext.cross_compile = true
      ext.cross_platform = ['i386-mswin32', 'i386-mingw32']
    end
  
    # cleanup versioned library directory
    CLEAN.include 'lib/{1.8,1.9}'
  end

  task :ragel => 'ext/puma_http11/http11_parser.c'
end

task :ext_clean do
  sh "rm -rf lib/puma_http11.bundle"
  sh "rm -rf lib/puma_http11.jar"
  sh "rm -rf lib/puma_http11.so"
end

task :clean => :ext_clean
