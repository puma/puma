# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "puma"
  s.version = "0.8.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Evan Phoenix"]
  s.date = "2011-10-25"
  s.description = "Puma is a small library that provides a very fast and concurrent HTTP 1.1 server for Ruby web applications.  It is designed for running rack apps only.\n\nWhat makes Puma so fast is the careful use of an Ragel extension to provide fast, accurate HTTP 1.1 protocol parsing. This makes the server scream without too many portability issues."
  s.email = ["evan@phx.io"]
  s.executables = ["puma"]
  s.extensions = ["ext/puma_http11/extconf.rb"]
  s.extra_rdoc_files = ["History.txt", "Manifest.txt"]
  s.files = ["COPYING", "History.txt", "LICENSE", "Manifest.txt", "README.md", "Rakefile", "TODO", "bin/puma", "examples/builder.rb", "examples/camping/README", "examples/camping/blog.rb", "examples/camping/tepee.rb", "examples/httpd.conf", "examples/mime.yaml", "examples/mongrel.conf", "examples/monitrc", "examples/random_thrash.rb", "examples/simpletest.rb", "examples/webrick_compare.rb", "ext/puma_http11/Http11Service.java", "ext/puma_http11/ext_help.h", "ext/puma_http11/extconf.rb", "ext/puma_http11/puma_http11.c", "ext/puma_http11/http11_parser.c", "ext/puma_http11/http11_parser.h", "ext/puma_http11/http11_parser.java.rl", "ext/puma_http11/http11_parser.rl", "ext/puma_http11/http11_parser_common.rl", "ext/puma_http11/org/jruby/mongrel/Http11.java", "ext/puma_http11/org/jruby/mongrel/Http11Parser.java", "lib/puma.rb", "lib/puma/cli.rb", "lib/puma/const.rb", "lib/puma/events.rb", "lib/puma/gems.rb", "lib/puma/mime_types.yml", "lib/puma/server.rb", "lib/puma/thread_pool.rb", "lib/puma/utils.rb", "lib/rack/handler/puma.rb", "puma.gemspec", "tasks/gem.rake", "tasks/java.rake", "tasks/native.rake", "tasks/ragel.rake", "test/lobster.ru", "test/mime.yaml", "test/test_http10.rb", "test/test_http11.rb", "test/test_persistent.rb", "test/test_rack_handler.rb", "test/test_rack_server.rb", "test/test_thread_pool.rb", "test/test_unix_socket.rb", "test/test_ws.rb", "test/testhelp.rb", "tools/trickletest.rb", ".gemtest"]
  s.rdoc_options = ["--main", "README.md"]
  s.require_paths = ["lib"]
  s.rubyforge_project = "puma"
  s.rubygems_version = "1.8.10"
  s.summary = "Puma is a small library that provides a very fast and concurrent HTTP 1.1 server for Ruby web applications"
  s.test_files = ["test/test_http10.rb", "test/test_http11.rb", "test/test_persistent.rb", "test/test_rack_handler.rb", "test/test_rack_server.rb", "test/test_thread_pool.rb", "test/test_unix_socket.rb", "test/test_ws.rb"]

  if s.respond_to? :specification_version then
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_development_dependency(%q<rake-compiler>, ["~> 0.7.0"])
      s.add_development_dependency(%q<hoe>, ["~> 2.10"])
    else
      s.add_dependency(%q<rake-compiler>, ["~> 0.7.0"])
      s.add_dependency(%q<hoe>, ["~> 2.10"])
    end
  else
    s.add_dependency(%q<rake-compiler>, ["~> 0.7.0"])
    s.add_dependency(%q<hoe>, ["~> 2.10"])
  end
end
