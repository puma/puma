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

setup_rdoc ['README', 'LICENSE', 'COPYING', 'lib/*.rb', 'doc/**/*.rdoc', 'ext/http11/http11.c']

desc "Does a full compile, test run"
task :default => [:compile, :test]

desc "Compiles all extensions"
task :compile => [:http11]
task :package => [:clean]

task :ragel do
  sh %{/usr/local/bin/ragel ext/http11/http11_parser.rl | /usr/local/bin/rlcodegen -G2 -o ext/http11/http11_parser.c}
end

task :site do
  sh %{pushd doc/site; webgen; scp -r output/* #{ENV['SSH_USER']}@rubyforge.org:/var/www/gforge-projects/mongrel/; popd }
  sh %{ scp -r doc/rdoc/* #{ENV['SSH_USER']}@rubyforge.org:/var/www/gforge-projects/mongrel/rdoc/ }
end

setup_extension("http11", "http11")

version="0.3.6"
summary = "A small fast HTTP library and server that runs Rails, Camping, and Nitro apps."
test_file = "test/test_ws.rb"
author="Zed A. Shaw"
name="mongrel"
scripts=['mongrel_rails']

setup_gem(name, version,  author, summary, scripts, test_file) do |spec|
  spec.add_dependency('daemons', '>= 0.4.2')
end

desc "Build a binary gem for Win32"
task :win32_gem => [:clean, :compile, :test, :rerdoc, :package_win32]

scripts_win32 = scripts + ['mongrel_rails_service','mongrel_rails_svc']
task :package_win32 do
  setup_win32_gem(name, version,  version, summary, scripts_win32, test_file) do |spec|
    spec.add_dependency('win32-service', '>= 0.5.0')
    spec.files << 'ext/http11/http11.so'
    spec.extensions = []
    spec.platform = Gem::Platform::WIN32
  end
end

