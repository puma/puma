
require 'rubygems'
gem 'echoe', '>=2.6.4'
require 'echoe'

Echoe.new("mongrel") do |p|
  p.summary = "A small fast HTTP library and server that runs Rails, Camping, Nitro and Iowa apps."
  p.author ="Zed A. Shaw"
  p.clean_pattern = ["ext/http11/*.{bundle,so,o,obj,pdb,lib,def,exp}", "ext/http11/Makefile", "pkg", "lib/*.bundle", "*.gem", "doc/site/output", ".config"]
  p.rdoc_pattern = ['README', 'LICENSE', 'COPYING', 'lib/**/*.rb', 'doc/**/*.rdoc', 'ext/http11/http11.c']
  p.ignore_pattern = /^(pkg|site|projects|doc|log)|CVS|\.log/
  p.ruby_version = '>= 1.8.4'
  p.dependencies = ['gem_plugin >=0.2.3', 'cgi_multipart_eof_fix >=2.4']

  p.need_tar_gz = false
  p.need_tgz = true
  p.require_signed = true

  case RUBY_PLATFORM 
  when /mswin/
    p.certificate_chain = ['~/gem_certificates/mongrel-public_cert.pem', 
      '~/gem_certificates/luislavena-mongrel-public_cert.pem']
  else
    p.certificate_chain = ['~/p/configuration/gem_certificates/mongrel/mongrel-public_cert.pem', 
      '~/p/configuration/gem_certificates/evan_weaver-mongrel-public_cert.pem']
  end

  p.eval = proc do  
    case RUBY_PLATFORM
    when /mswin/
      extensions.clear
      self.files += ['lib/http11.so']
      self.platform = Gem::Platform::WIN32
    when /jruby/
      extensions.clear
      self.files += ['lib/http11.jar']
      self.platform = 'jruby'        
    else
      add_dependency('daemons', '>= 1.0.3')
      add_dependency('fastthread', '>= 1.0.1')
    end
  end
  
end

#### A hack around RubyGems and Echoe for pre-compiled extensions.

extension = "ext/http11/extconf.rb"
extension_dir = File.dirname(extension)

def move_extensions
  Dir["#{extension_dir}/*.#{Config::CONFIG['DLEXT']}"].each { |file| cp file, "lib/" }
end

case RUBY_PLATFORM
when /mswin/
  filename = "lib/http11.so"
  file filename do
    Dir.chdir(extension_dir) do 
      ruby File.basename(extension)
      system(PLATFORM =~ /win32/ ? 'nmake' : 'make')
    end
    move_extensions
  end 
  task :compile => [filename]

when /jruby/
  filename = "lib/http11.jar"
  file filename do
    Dir.chdir(extension_dir) { sh "ant jar" }
    move_extensions      
  end      
  task :compile => [filename]
end

#### Project-wide install and uninstall tasks

def sub_project(project, *targets)
  targets.each do |target|
    Dir.chdir "projects/#{project}" do
      sh %{rake --trace #{target.to_s} }
    end
  end
end

task :package_all => [:package] do
  sub_project("gem_plugin", :clean, :package)
  sub_project("cgi_multipart_eof_fix", :clean, :package)
  sub_project("fastthread", :clean, :package)
  sub_project("mongrel_status", :clean, :package)
  sub_project("mongrel_upload_progress", :clean, :package)
  sub_project("mongrel_console", :clean, :package)
  sub_project("mongrel_cluster", :clean, :package)
  if RUBY_PLATFORM =~ /mswin/
    sub_project("mongrel_service", :clean, :package)
  end
end


task :install_requirements do
  # These run before Mongrel is installed
  sub_project("gem_plugin", :install)
  sub_project("cgi_multipart_eof_fix", :install)
  sub_project("fastthread", :install)
end

task :install => [:install_requirements] do
  # These run after Mongrel is installed
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
  sub_project("cgi_multipart_eof_fix", :uninstall)
  sub_project("mongrel_upload_progress", :uninstall)
  sub_project("mongrel_console", :uninstall)
  sub_project("gem_plugin", :uninstall)
  sub_project("fastthread", :uninstall)
  if RUBY_PLATFORM =~ /mswin/
    sub_project("mongrel_service", :install)
  end
end

#### Extra upload tasks

task :gem_source => [:package_all] do
  rm_rf "pkg/gems"
  rm_rf "pkg/tars"
  mkdir_p "pkg/gems"
  mkdir_p "pkg/tars"
 
  FileList["**/*.gem"].each { |gem| mv gem, "pkg/gems" }
  FileList["**/*.tgz"].each {|tgz| mv tgz, "pkg/tars" }
  
  # XXX Hack
  sh %{ cp ~/Downloads/mongrel-1.0.2-mswin32.gem pkg/gems/ }
  sh %{ cp ~/Downloads/mongrel_service-0.3.3-mswin32.gem pkg/gems/ }
  
  sh %{ rm -rf pkg/mongrel* }

  sh %{ index_gem_repository.rb -d pkg }
  sh %{ scp -r CHANGELOG pkg/* rubyforge.org:/var/www/gforge-projects/mongrel/releases/ }
  sh %{ svn log -v > SVN_LOG }
  sh %{ scp -r SVN_LOG pkg/* rubyforge.org:/var/www/gforge-projects/mongrel/releases/ }
end

task :ragel do
  sh %{ragel ext/http11/http11_parser.rl | rlgen-cd -G2 -o ext/http11/http11_parser.c}
end

task :site_webgen do
  sh %{pushd site; webgen; ruby atom.rb > output/feed.atom; rsync -azv output/* rubyforge.org:/var/www/gforge-projects/mongrel/; popd }
end

task :site_rdoc => [:redoc] do
  sh %{ rsync -azv doc/* rubyforge.org:/var/www/gforge-projects/mongrel/rdoc/ }
end

task :site_coverage => [:rcov] do
  sh %{ rsync -azv test/coverage/* rubyforge.org:/var/www/gforge-projects/mongrel/coverage/ }
end

task :site_projects_rdoc do
  sh %{ cd projects/gem_plugin; rake site }
end

task :site => [:site_webgen, :site_rdoc, :site_coverage, :site_projects_rdoc]
