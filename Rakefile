require 'rake'
require 'rake/testtask'
require 'rake/clean'
require 'rake/gempackagetask'
require 'rake/rdoctask'
require 'tools/rakehelp'
require 'fileutils'
include FileUtils

setup_tests
setup_clean ["ext/http11/*.{bundle,so,obj,pdb,lib,def,exp}", "ext/http11/Makefile", "pkg", "lib/*.bundle", "*.gem", "doc/site/output", ".config"]

setup_rdoc ['README', 'LICENSE', 'COPYING', 'lib/**/*.rb', 'doc/**/*.rdoc', 'ext/http11/http11.c']

desc "Does a full compile, test run"
task :default => [:compile, :test]

desc "Compiles all extensions"
task :compile => [:http11]
task :package => [:clean,:compile,:test]

task :ragel do
  sh %{/usr/local/bin/ragel ext/http11/http11_parser.rl | /usr/local/bin/rlcodegen -G2 -o ext/http11/http11_parser.c}
end

task :site do
  sh %{pushd doc/site; webgen; scp -r output/* #{ENV['SSH_USER']}@rubyforge.org:/var/www/gforge-projects/mongrel/; popd }
  sh %{ scp -r doc/rdoc/* #{ENV['SSH_USER']}@rubyforge.org:/var/www/gforge-projects/mongrel/rdoc/ }
  sh %{ cd projects/gem_plugin; rake site }
end

setup_extension("http11", "http11")

name="mongrel"
version="0.3.10.1"

setup_gem(name, version) do |spec|
  spec.summary = "A small fast HTTP library and server that runs Rails, Camping, and Nitro apps."
  spec.description = spec.summary
  spec.test_file = "test/test_ws.rb"
  spec.author="Zed A. Shaw"
  spec.executables=['mongrel_rails']
  spec.files += %w(ext/http11/MANIFEST README Rakefile setup.rb)

  spec.add_dependency('daemons', '>= 0.4.2')
  spec.add_dependency('gem_plugin', '>= 0.2')
  spec.required_ruby_version = '>= 1.8.4'
end

desc "Build a binary gem for Win32"
task :win32_gem => [:clean, :compile, :test, :rerdoc, :package_win32]

task :package_win32 do
  setup_win32_gem(name, version) do |spec|
    spec.summary = "A small fast HTTP library and server that runs Rails, Camping, and Nitro apps."
    spec.description = spec.summary
    spec.test_files = Dir.glob('test/test_*.rb') 
    spec.author="Zed A. Shaw"
    spec.executables=['mongrel_rails', 'mongrel_rails_service']
    spec.homepage="http://mongrel.rubyforge.org"
    spec.rubyforge_project="mongrel"
    spec.files += %w(ext/http11/MANIFEST README Rakefile setup.rb)
    spec.files << 'ext/http11/http11.so'

    spec.required_ruby_version = '>= 1.8.4'

    spec.add_dependency('win32-service', '>= 0.5.0')
    spec.add_dependency('gem_plugin', ">= 0.2")

    spec.extensions = []
    spec.platform = Gem::Platform::WIN32
  end
end


task :install do
  sub_project("gem_plugin", :install)
  sh %{rake package}
  sh %{sudo gem install pkg/mongrel-#{version}}
  sub_project("mongrel_status", :install)
  sub_project("mongrel_config", :install)
end

task :uninstall => [:clean] do
  sub_project("mongrel_status", :uninstall)
  sub_project("mongrel_config", :uninstall)
  sh %{sudo gem uninstall mongrel}
  sub_project("gem_plugin", :uninstall)
end


task :gem_source => [:clean, :package] do
  sub_project "gem_plugin", :clean, :test, :package
  sub_project "mongrel_config", :clean, :test, :package
  sub_project "mongrel_status", :clean, :test, :package

  mkdir_p "pkg/gems"

  FileList["**/*.gem"].each { |gem| mv gem, "pkg/gems" }
  FileList["pkg/*.tgz"].each {|tgz| rm tgz }
  rm_rf "pkg/#{name}-#{version}"

  sh %{ generate_yaml_index.rb -d pkg }
  sh %{ scp -r pkg/* #{ENV['SSH_USER']}@rubyforge.org:/var/www/gforge-projects/mongrel/releases/ }
end
