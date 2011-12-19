# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "puma"
  s.version = "0.9.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Evan Phoenix"]
  s.date = "2011-12-19"
  s.description = "Puma is a small library that provides a very fast and concurrent HTTP 1.1 server for Ruby web applications.  It is designed for running rack apps only.\n\nWhat makes Puma so fast is the careful use of an Ragel extension to provide fast, accurate HTTP 1.1 protocol parsing. This makes the server scream without too many portability issues."
  s.email = ["evan@phx.io"]
  s.executables = ["puma", "pumactl"]
  s.extensions = ["ext/puma_http11/extconf.rb"]
  s.extra_rdoc_files = ["History.txt", "Manifest.txt"]
  s.files = ["COPYING", "Gemfile", "History.txt", "LICENSE", "Manifest.txt", "README.md", "Rakefile", "TODO", "bin/puma", "bin/pumactl", "examples/config.rb", "ext/puma_http11/PumaHttp11Service.java", "ext/puma_http11/ext_help.h", "ext/puma_http11/extconf.rb", "ext/puma_http11/http11_parser.c", "ext/puma_http11/http11_parser.h", "ext/puma_http11/http11_parser.java.rl", "ext/puma_http11/http11_parser.rl", "ext/puma_http11/http11_parser_common.rl", "ext/puma_http11/org/jruby/puma/Http11.java", "ext/puma_http11/org/jruby/puma/Http11Parser.java", "ext/puma_http11/puma_http11.c", "lib/puma.rb", "lib/puma/app/status.rb", "lib/puma/cli.rb", "lib/puma/config.rb", "lib/puma/const.rb", "lib/puma/control_cli.rb", "lib/puma/events.rb", "lib/puma/jruby_restart.rb", "lib/puma/null_io.rb", "lib/puma/rack_patch.rb", "lib/puma/server.rb", "lib/puma/thread_pool.rb", "lib/rack/handler/puma.rb", "puma.gemspec", "test/ab_rs.rb", "test/lobster.ru", "test/mime.yaml", "test/test_app_status.rb", "test/test_cli.rb", "test/test_http10.rb", "test/test_http11.rb", "test/test_persistent.rb", "test/test_rack_handler.rb", "test/test_rack_server.rb", "test/test_thread_pool.rb", "test/test_unix_socket.rb", "test/test_ws.rb", "test/testhelp.rb", "tools/trickletest.rb", "test/test_config.rb", "test/test_integration.rb"]
  s.rdoc_options = ["--main", "README.md"]
  s.require_paths = ["lib"]
  s.rubyforge_project = "puma"
  s.rubygems_version = "1.8.12"
  s.summary = "Puma is a small library that provides a very fast and concurrent HTTP 1.1 server for Ruby web applications"
  s.test_files = ["test/test_app_status.rb", "test/test_cli.rb", "test/test_config.rb", "test/test_http10.rb", "test/test_http11.rb", "test/test_integration.rb", "test/test_persistent.rb", "test/test_rack_handler.rb", "test/test_rack_server.rb", "test/test_thread_pool.rb", "test/test_unix_socket.rb", "test/test_ws.rb"]

  if s.respond_to? :specification_version then
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<rack>, ["~> 1.2"])
      s.add_development_dependency(%q<rake-compiler>, ["~> 0.7.0"])
      s.add_development_dependency(%q<hoe>, ["~> 2.10"])
    else
      s.add_dependency(%q<rack>, ["~> 1.2"])
      s.add_dependency(%q<rake-compiler>, ["~> 0.7.0"])
      s.add_dependency(%q<hoe>, ["~> 2.10"])
    end
  else
    s.add_dependency(%q<rack>, ["~> 1.2"])
    s.add_dependency(%q<rake-compiler>, ["~> 0.7.0"])
    s.add_dependency(%q<hoe>, ["~> 2.10"])
  end
end
