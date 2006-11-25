require 'rake'
require 'rake/clean'
require 'rake/testtask'
require 'rake/gempackagetask'
require 'tools/rakehelp'

VERSION="0.4"

task :default => ['fastthread', 'test', 'package']

setup_extension('fastthread', 'fastthread')

Rake::TestTask.new do |task|
  task.libs << 'test'
  task.test_files = Dir.glob( 'test/test*.rb' )
  task.verbose = true
end

gemspec = Gem::Specification.new do |gemspec|
  gemspec.name = "fastthread"
  gemspec.version = VERSION
  gemspec.platform = Gem::Platform::RUBY
  gemspec.author = "MenTaLguY <mental@rydia.net>"
  gemspec.summary = "Optimized replacement for thread.rb primitives"
  gemspec.test_file = 'test/test_all.rb'
  gemspec.extensions = Dir.glob( 'ext/**/extconf.rb' )
  gemspec.files = %w( Rakefile ) +
                  Dir.glob( 'test/*.rb' ) +
                  Dir.glob( 'ext/**/*.{c,rb}' )
  gemspec.require_path = 'ext'
end

Rake::GemPackageTask.new( gemspec ) do |task|
  task.gem_spec = gemspec
  task.need_tar = true
end

setup_clean ["ext/fastthread/*.{bundle,so,obj,pdb,lib,def,exp}", "ext/fastthread/Makefile", "pkg", "lib/*.bundle", "*.gem", ".config"]

task :install => [:default] do
  sh %{ sudo gem install pkg/fastthread-#{VERSION}.gem }
end

task :uninstall do
  sh %{ sudo gem uninstall fastthread }
end
