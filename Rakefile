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
task :compile => [:http11] do
  if Dir.glob(File.join("lib","http11.*")).length == 0
    STDERR.puts "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    STDERR.puts "Gem actually failed to build.  Your system is"
    STDERR.puts "NOT configured properly to build Mongrel."
    STDERR.puts "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    exit(1)
  end
end

task :package => [:clean,:compile,:test,:rerdoc]

task :ragel do
  sh %{/usr/local/bin/ragel ext/http11/http11_parser.rl | /usr/local/bin/rlcodegen -G2 -o ext/http11/http11_parser.c}
end

task :site_webgen do
  sh %{pushd doc/site; webgen; ruby atom.rb > output/feed.atom; scp -r output/* #{ENV['SSH_USER']}@rubyforge.org:/var/www/gforge-projects/mongrel/; popd }
end

task :site_rdoc do
  sh %{ scp -r doc/rdoc/* #{ENV['SSH_USER']}@rubyforge.org:/var/www/gforge-projects/mongrel/rdoc/ }
end

task :site_coverage => [:rcov] do
  sh %{ scp -r test/coverage/* #{ENV['SSH_USER']}@rubyforge.org:/var/www/gforge-projects/mongrel/coverage/ }
end

task :site_projects_rdoc do
  sh %{ cd projects/gem_plugin; rake site }
end

task :site => [:site_webgen, :site_rdoc, :site_coverage, :site_projects_rdoc]

setup_extension("http11", "http11")

name="mongrel"
version="0.3.18"

setup_gem(name, version) do |spec|
  spec.summary = "A small fast HTTP library and server that runs Rails, Camping, Nitro and Iowa apps."
  spec.description = spec.summary
  spec.test_files = Dir.glob('test/test_*.rb')
  spec.author="Zed A. Shaw"
  spec.executables=['mongrel_rails']
  spec.files += %w(ext/http11/MANIFEST README Rakefile setup.rb)

  spec.required_ruby_version = '>= 1.8.4'

  if RUBY_PLATFORM =~ /mswin/
    spec.files += ['lib/http11.so']
    spec.extensions.clear
    spec.platform = Gem::Platform::WIN32
  else
    spec.add_dependency('daemons', '>= 0.4.2')
  end
  
  spec.add_dependency('gem_plugin', '>= 0.2.1')
  spec.add_dependency('cgi_multipart_eof_fix', '>= 0.2.1')
end

task :install do
  sub_project("gem_plugin", :install)
  sub_project("fastthread", :install)
  sh %{rake package}
  sh %{gem install pkg/mongrel-#{version}}
  sub_project("mongrel_status", :install)
  sub_project("mongrel_upload_progress", :install)
  sub_project("mongrel_console", :install)
  sub_project("mongrel_cluster", :install)
  if RUBY_PLATFORM =~ /mswin/
    sub_project("mongrel_service", :install)
  end
end

task :uninstall => [:clean] do
  sub_project("mongrel_status", :uninstall)
  sub_project("mongrel_upload_progress", :uninstall)
  sub_project("mongrel_console", :uninstall)
  sh %{gem uninstall mongrel}
  sub_project("gem_plugin", :uninstall)
  sub_project("fastthread", :uninstall)
  if RUBY_PLATFORM =~ /mswin/
    sub_project("mongrel_service", :install)
  end
end


task :gem_source do
  mkdir_p "pkg/gems"
 
  FileList["**/*.gem"].each { |gem| mv gem, "pkg/gems" }
  FileList["pkg/*.tgz"].each {|tgz| rm tgz }
  rm_rf "pkg/#{name}-#{version}"

  sh %{ index_gem_repository.rb -d pkg }
  sh %{ scp -r ChangeLog pkg/* #{ENV['SSH_USER']}@rubyforge.org:/var/www/gforge-projects/mongrel/releases/ }
end
