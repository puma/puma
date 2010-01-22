
# the following tasks ease the build of C file from Ragel one

file 'ext/http11/http11_parser.c' => ['ext/http11/http11_parser.rl'] do |t|
  begin
    sh "ragel #{t.prerequisites.last} -C -G2 -o #{t.name}"
  rescue
    fail "Could not build wrapper using Ragel (it failed or not installed?)"
  end
end

file 'ext/http11/org/jruby/mongrel/Http11Parser.java' => ['ext/http11/http11_parser.java.rl'] do |t|
  begin
    sh "ragel #{t.prerequisites.last} -J -G2 -o #{t.name}"
  rescue
    fail "Could not build wrapper using Ragel (it failed or not installed?)"
  end
end

task :ragel => (defined?(JRUBY_VERSION) ? 'ext/http11/org/jruby/mongrel/Http11Parser.java' : 'ext/http11/http11_parser.c')
