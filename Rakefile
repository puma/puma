
require 'rubygems'
gem 'echoe', '>=2.6.4'
require 'echoe'

e = Echoe.new("mongrel") do |p|
  p.summary = "A small fast HTTP library and server that runs Rails, Camping, Nitro and Iowa apps."
  p.author ="Zed A. Shaw"
  p.clean_pattern = ['ext/http11/*.{bundle,so,o,obj,pdb,lib,def,exp}', 'ext/http11/Makefile', 'pkg', 'lib/*.bundle', '*.gem', 'doc/site/output', '.config', 'lib/http11.jar', 'ext/http11_java/classes']
  p.rdoc_pattern = ['README', 'LICENSE', 'COPYING', 'lib/**/*.rb', 'doc/**/*.rdoc', 'ext/http11/http11.c']
  p.ignore_pattern = /^(pkg|site|projects|doc|log)|CVS|\.log/
  p.ruby_version = '>= 1.8.4'
  p.dependencies = ['gem_plugin >=0.2.3', 'cgi_multipart_eof_fix >=2.4']

  p.need_tar_gz = false
  p.need_tgz = true

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
    when /java/
      extensions.clear
      self.files += ['lib/http11.jar']
      self.platform = 'jruby'
    else
      add_dependency('daemons', '>= 1.0.3')
      add_dependency('fastthread', '>= 1.0.1')
    end
  end
  
end

#### Ragel builder

task :ragel do
  Dir.chdir "ext/http11" do
    target = "http11_parser.c"
    File.unlink target if File.exist? target
    sh "ragel http11_parser.rl | rlgen-cd -G2 -o #{target}"
    raise "Failed to build C source" unless File.exist? target
  end
  Dir.chdir "ext/http11" do
    target = "../../ext/http11_java/org/jruby/mongrel/Http11Parser.java"
    File.unlink target if File.exist? target
    sh "ragel -J http11_parser.java.rl | rlgen-java -o #{target}"
    raise "Failed to build Java source" unless File.exist? target
  end
end

#### XXX Hack around JRuby test/unit interaction problems

task :test_java do
  e.test_pattern.each do |f|
    sh "/opt/local/jruby/bin/jruby -w -Ilib:ext:bin:test -e 'require \"#{f}\"'" rescue nil
  end
end

#### XXX Hack around RubyGems and Echoe for pre-compiled extensions.

def move_extensions
  Dir["ext/**/*.#{Config::CONFIG['DLEXT']}"].each { |file| cp file, "lib/" }
end

def java_classpath_arg 
  # A myriad of ways to discover the JRuby classpath
  classpath = begin
    require 'java' 
    # Already running in a JRuby JVM
    Java::java.lang.System.getProperty('java.class.path')
  rescue LoadError
    ENV['JRUBY_PARENT_CLASSPATH'] || ENV['JRUBY_HOME'] && FileList["#{ENV['JRUBY_HOME']}/lib/*.jar"].join(File::PATH_SEPARATOR)
  end
  classpath ? "-cp #{classpath}" : ""
end

case RUBY_PLATFORM
when /mswin/
  filename = "lib/http11.so"
  file filename do
    Dir.chdir("ext/http11") do 
      ruby "extconf.rb"
      system(PLATFORM =~ /mswin/ ? 'nmake' : 'make')
    end
    move_extensions
  end 
  task :compile => [filename]

when /java/
  filename = "lib/http11.jar"
  file filename do
    build_dir = "ext/http11_java/classes"
    mkdir_p build_dir
    sources = FileList['ext/http11_java/**/*.java'].join(' ')
    sh "javac -target 1.4 -source 1.4 -d #{build_dir} #{java_classpath_arg} #{sources}"
    sh "jar cf lib/http11.jar -C #{build_dir} ."
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
  sh "cp ~/Downloads/mongrel-1.0.2-mswin32.gem pkg/gems/"
  sh "cp ~/Downloads/mongrel_service-0.3.3-mswin32.gem pkg/gems/"  
  sh "rm -rf pkg/mongrel*"
  sh "index_gem_repository.rb -d pkg"  
  sh "scp -r CHANGELOG pkg/* rubyforge.org:/var/www/gforge-projects/mongrel/releases/" 
  sh "svn log -v > SVN_LOG"
  sh "scp -r SVN_LOG pkg/* rubyforge.org:/var/www/gforge-projects/mongrel/releases/" 
  rm "SVN_LOG"  
end

task :site_webgen do
  sh "pushd site; webgen; ruby atom.rb > output/feed.atom; rsync -azv output/* rubyforge.org:/var/www/gforge-projects/mongrel/; popd"
end

task :site_rdoc => [:redoc] do
  sh "rsync -azv doc/* rubyforge.org:/var/www/gforge-projects/mongrel/rdoc/"
end

task :site_coverage => [:rcov] do
  sh "rsync -azv test/coverage/* rubyforge.org:/var/www/gforge-projects/mongrel/coverage/"
end

task :site_projects_rdoc do
  sh "cd projects/gem_plugin; rake site"
end

task :site => [:site_webgen, :site_rdoc, :site_coverage, :site_projects_rdoc]
