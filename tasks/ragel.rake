
# the following tasks ease the build of C file from Ragel one

file 'ext/puma_http11/http11_parser.c' => ['ext/puma_http11/http11_parser.rl'] do |t|
  begin
    sh "ragel #{t.prerequisites.last} -C -G2 -o #{t.name}"
  rescue
    fail "Could not build wrapper using Ragel (it failed or not installed?)"
  end
end

file 'ext/puma_http11/org/jruby/puma/Http11Parser.java' => ['ext/puma_http11/http11_parser.java.rl'] do |t|
  begin
    sh "ragel #{t.prerequisites.last} -J -G2 -o #{t.name}"
  rescue
    fail "Could not build wrapper using Ragel (it failed or not installed?)"
  end
end

if IS_JRUBY
  task :ragel => 'ext/puma_http11/org/jruby/puma/Http11Parser.java'
else
  task :ragel => 'ext/puma_http11/http11_parser.c'
end
