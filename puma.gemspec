# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "puma"
  s.version = "2.0.0.b1"

  s.required_rubygems_version = Gem::Requirement.new("> 1.3.1") if s.respond_to? :required_rubygems_version=
  s.authors = ["Evan Phoenix"]
  s.date = "2012-10-24"
  s.description = "Puma is a simple, fast, and highly concurrent HTTP 1.1 server for Ruby web applications. It can be used with any application that supports Rack, and is considered the replacement for Webrick and Mongrel. It was designed to be the go-to server for [Rubinius](http://rubini.us), but also works well with JRuby and MRI. Puma is intended for use in both development and production environments.\n\nUnder the hood, Puma processes requests using a C-optimized Ragel extension (inherited from Mongrel) that provides fast, accurate HTTP 1.1 protocol parsing in a portable way. Puma then serves the request in a thread from an internal thread pool (which you can control). This allows Puma to provide real concurrency for your web application!\n\nWith Rubinius 2.0, Puma will utilize all cores on your CPU with real threads, meaning you won't have to spawn multiple processes to increase throughput. You can expect to see a similar benefit from JRuby.\n\nOn MRI, there is a Global Interpreter Lock (GIL) that ensures only one thread can be run at a time. But if you're doing a lot of blocking IO (such as HTTP calls to external APIs like Twitter), Puma still improves MRI's throughput by allowing blocking IO to be run concurrently (EventMachine-based servers such as Thin turn off this ability, requiring you to use special libraries). Your mileage may vary. In order to get the best throughput, it is highly recommended that you use a Ruby implementation with real threads like [Rubinius](http://rubini.us) or [JRuby](http://jruby.org)."
  s.email = ["evan@phx.io"]
  s.executables = ["puma", "pumactl"]
  s.extensions = ["ext/puma_http11/extconf.rb"]
  s.extra_rdoc_files = ["History.txt", "Manifest.txt"]
  s.files = [".travis.yml", "COPYING", "Gemfile", "Gemfile.lock", "History.txt", "LICENSE", "Manifest.txt", "README.md", "Rakefile", "bin/puma", "bin/pumactl", "docs/config.md", "docs/nginx.md", "examples/CA/cacert.pem", "examples/CA/newcerts/cert_1.pem", "examples/CA/newcerts/cert_2.pem", "examples/CA/private/cakeypair.pem", "examples/CA/serial", "examples/config.rb", "examples/puma/cert_puma.pem", "examples/puma/csr_puma.pem", "examples/puma/keystore.jks", "examples/puma/puma_keypair.pem", "examples/qc_config.rb", "ext/puma_http11/PumaHttp11Service.java", "ext/puma_http11/ext_help.h", "ext/puma_http11/extconf.rb", "ext/puma_http11/http11_parser.c", "ext/puma_http11/http11_parser.h", "ext/puma_http11/http11_parser.java.rl", "ext/puma_http11/http11_parser.rl", "ext/puma_http11/http11_parser_common.rl", "ext/puma_http11/io_buffer.c", "ext/puma_http11/mini_ssl.c", "ext/puma_http11/org/jruby/puma/Http11.java", "ext/puma_http11/org/jruby/puma/Http11Parser.java", "ext/puma_http11/org/jruby/puma/MiniSSL.java", "ext/puma_http11/puma_http11.c", "lib/puma.rb", "lib/puma/accept_nonblock.rb", "lib/puma/app/status.rb", "lib/puma/binder.rb", "lib/puma/capistrano.rb", "lib/puma/cli.rb", "lib/puma/client.rb", "lib/puma/compat.rb", "lib/puma/configuration.rb", "lib/puma/const.rb", "lib/puma/control_cli.rb", "lib/puma/daemon_ext.rb", "lib/puma/delegation.rb", "lib/puma/detect.rb", "lib/puma/events.rb", "lib/puma/io_buffer.rb", "lib/puma/java_io_buffer.rb", "lib/puma/jruby_restart.rb", "lib/puma/minissl.rb", "lib/puma/null_io.rb", "lib/puma/rack_patch.rb", "lib/puma/reactor.rb", "lib/puma/server.rb", "lib/puma/thread_pool.rb", "lib/rack/handler/puma.rb", "puma.gemspec", "test/ab_rs.rb", "test/config/app.rb", "test/hello-post.ru", "test/hello.ru", "test/lobster.ru", "test/mime.yaml", "test/shell/run.sh", "test/shell/t1.rb", "test/shell/t1_conf.rb", "test/slow.ru", "test/test_app_status.rb", "test/test_cli.rb", "test/test_config.rb", "test/test_http10.rb", "test/test_http11.rb", "test/test_integration.rb", "test/test_iobuffer.rb", "test/test_null_io.rb", "test/test_persistent.rb", "test/test_puma_server.rb", "test/test_rack_handler.rb", "test/test_rack_server.rb", "test/test_thread_pool.rb", "test/test_unix_socket.rb", "test/test_ws.rb", "test/testhelp.rb", "tools/jungle/README.md", "tools/jungle/puma", "tools/jungle/run-puma", "tools/trickletest.rb"]
  s.homepage = "http://puma.io"
  s.rdoc_options = ["--main", "README.md"]
  s.require_paths = ["lib"]
  s.required_ruby_version = Gem::Requirement.new(">= 1.8.7")
  s.rubyforge_project = "puma"
  s.rubygems_version = "1.8.24"
  s.summary = "Puma is a simple, fast, and highly concurrent HTTP 1.1 server for Ruby web applications"
  s.test_files = ["test/test_iobuffer.rb", "test/test_persistent.rb", "test/test_ws.rb", "test/test_cli.rb", "test/test_http11.rb", "test/test_config.rb", "test/test_rack_handler.rb", "test/test_null_io.rb", "test/test_app_status.rb", "test/test_thread_pool.rb", "test/test_unix_socket.rb", "test/test_rack_server.rb", "test/test_integration.rb", "test/test_http10.rb", "test/test_puma_server.rb"]

  if s.respond_to? :specification_version then
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<rack>, ["~> 1.2"])
      s.add_development_dependency(%q<rdoc>, ["~> 3.10"])
      s.add_development_dependency(%q<rake-compiler>, ["~> 0.8.0"])
      s.add_development_dependency(%q<hoe>, ["~> 3.1"])
    else
      s.add_dependency(%q<rack>, ["~> 1.2"])
      s.add_dependency(%q<rdoc>, ["~> 3.10"])
      s.add_dependency(%q<rake-compiler>, ["~> 0.8.0"])
      s.add_dependency(%q<hoe>, ["~> 3.1"])
    end
  else
    s.add_dependency(%q<rack>, ["~> 1.2"])
    s.add_dependency(%q<rdoc>, ["~> 3.10"])
    s.add_dependency(%q<rake-compiler>, ["~> 0.8.0"])
    s.add_dependency(%q<hoe>, ["~> 3.1"])
  end
end
