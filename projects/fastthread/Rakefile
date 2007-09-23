
require 'echoe'

Echoe.new("fastthread") do |p|
  p.project = "mongrel"
  p.author = "MenTaLguY <mental@rydia.net>"
  p.summary = "Optimized replacement for thread.rb primitives"
  p.extensions = "ext/fastthread/extconf.rb"
  p.clean_pattern = ['build/*', '**/*.o', '**/*.so', '**/*.a', 'lib/*-*', '**/*.log', "ext/fastthread/*.{bundle,so,obj,pdb,lib,def,exp}", "ext/fastthread/Makefile", "pkg", "lib/*.bundle", "*.gem", ".config"]

  p.need_tar_gz = false
  p.need_tgz = true
  p.certificate_chain = ['/Users/eweaver/p/configuration/gem_certificates/mongrel/mongrel-public_cert.pem',
    '/Users/eweaver/p/configuration/gem_certificates/evan_weaver-mongrel-public_cert.pem']    
  p.require_signed = true

  p.eval = proc do  
    if RUBY_PLATFORM.match("win32")
      platform = Gem::Platform::WIN32
      files += ['lib/fastthread.so']
      task :package => [:clean, :compile]
    end
  end

end
