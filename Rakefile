
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

  unless RUBY_PLATFORM =~ /mswin/
    self.certificate_chain = ['~/p/configuration/gem_certificates/mongrel/mongrel-public_cert.pem',
      '~/p/configuration/gem_certificates/evan_weaver-mongrel-public_cert.pem']
  else
    self.certificate_chain = ['~/gem_certificates/mongrel-public_cert.pem',
                              '~/gem_certificates/luislavena-mongrel-public_cert.pem']
  end

  p.eval = proc do  
    if RUBY_PLATFORM =~ /mswin/
      self.files += ['lib/http11.so']
      extensions.clear
      self.platform = Gem::Platform::WIN32
    else
      add_dependency('daemons', '>= 1.0.3')
      add_dependency('fastthread', '>= 1.0.1')
    end
  end
end

# NOTE: a big HACK around RubyGems and Echoe for pre-compiled extensions.
# as usual, just for win32... to make it happy.
# starting to feel the pain...
file "lib/http11.so" do
  extension = "ext/http11/extconf.rb"
  directory = File.dirname(extension)
  Dir.chdir(directory) do 
    ruby File.basename(extension)
    system(PLATFORM =~ /win32/ ? 'nmake' : 'make')
  end
  Dir["#{directory}/*.#{Config::CONFIG['DLEXT']}"].each do |file|
    cp file, "lib/"
  end
end if RUBY_PLATFORM =~ /mswin/

task :compile => ["lib/http11.so"] if RUBY_PLATFORM =~ /mswin/

#### Project-wide install and uninstall tasks

def sub_project(project, *targets)
  targets.each do |target|
    Dir.chdir "projects/#{project}" do
      sh %{rake --trace #{target.to_s} }
    end
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

#### Documentation upload tasks

# Is this still used?
task :gem_source do
  mkdir_p "pkg/gems"
  mkdir_p "pkg/tar"
 
  FileList["**/*.gem"].each { |gem| mv gem, "pkg/gems" }
  FileList["pkg/*.tgz"].each {|tgz| mv tgz, "pkg/tar" }
  rm_rf "pkg/#{name}-#{version}"

  sh %{ index_gem_repository.rb -d pkg }
  sh %{ scp -r ChangeLog pkg/* rubyforge.org:/var/www/gforge-projects/mongrel/releases/ }
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
