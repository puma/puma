require 'rake'
require 'rake/clean'
require 'rake/testtask'
require 'rake/gempackagetask'
require 'tools/rakehelp'

GEM_VERSION="1.0"

setup_extension('fastthread', 'fastthread')

desc "Compiles native extensions"
task :compile => [:fastthread]

task :default => [:compile, :test]

Rake::TestTask.new do |task|
  task.libs << 'test'
  task.test_files = Dir.glob( 'test/test*.rb' )
  task.verbose = true
end

gemspec = Gem::Specification.new do |gemspec|
  gemspec.name = "fastthread"
  gemspec.version = GEM_VERSION
  gemspec.author = "MenTaLguY <mental@rydia.net>"
  gemspec.summary = "Optimized replacement for thread.rb primitives"
  gemspec.test_file = 'test/test_all.rb'
  gemspec.files = %w( Rakefile setup.rb ) +
                  Dir.glob( 'test/*.rb' ) +
                  Dir.glob( 'ext/**/*.{c,rb}' ) +
                  Dir.glob( 'tools/*.rb' )
                  
  gemspec.require_path = 'lib'

  if RUBY_PLATFORM.match("win32")
    gemspec.platform = Gem::Platform::WIN32
    gemspec.files += ['lib/fastthread.so']
  else
    gemspec.platform = Gem::Platform::RUBY
    gemspec.extensions = Dir.glob( 'ext/**/extconf.rb' )
  end
end

task :package => [:clean, :compile, :test]
Rake::GemPackageTask.new( gemspec ) do |task|
  task.gem_spec = gemspec
  task.need_tar = true
end

setup_clean ["ext/fastthread/*.{bundle,so,obj,pdb,lib,def,exp}", "ext/fastthread/Makefile", "pkg", "lib/*.bundle", "*.gem", ".config"]

task :install => [:default, :package] do
  sh %{ sudo gem install pkg/fastthread-#{GEM_VERSION}.gem }
end

task :uninstall do
  sh %{ sudo gem uninstall fastthread }
end
