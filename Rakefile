require 'rake'
require 'rake/testtask'
require 'rake/clean'
require 'rake/gempackagetask'
require 'rake/rdoctask'
require 'tools/rakehelp'
require 'fileutils'
include FileUtils

setup_tests
setup_clean ["ext/http11/Makefile", "pkg", "lib/*.bundle", "ext/http11/*.bundle"]
setup_rdoc ['README', 'LICENSE', 'COPYING', 'lib/*.rb', 'doc/**/*.rdoc', 'ext/http11/http11.c']

desc "Does a full compile, test run"
task :default => [:compile, :test]

desc "Compiles all extensions"
task :compile => [:http11]
task :package => [:clean]

task :ragel do
	sh %{/usr/local/bin/ragel ext/http11/http11_parser.rl | /usr/local/bin/rlcodegen -G2 -o ext/http11/http11_parser.c}
end

setup_extension("http11", "http11")

summary = "A small fast HTTP library and server that runs Rails, Camping, and Nitro apps."
test_file = "test/test_ws.rb"
setup_gem("mongrel", "0.3.1",  "Zed A. Shaw", summary, ['mongrel_rails'], test_file) do |spec|
  spec.add_dependency('daemons', '>= 0.4.2')
end
