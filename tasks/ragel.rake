# the following tasks ease the build of C file from Ragel one
file 'ext/http11/http11_parser.c' => ['ext/http11/http11_parser.rl'] do |t|
  begin
    sh "ragel -G2 #{t.prerequisites.last} -o #{t.name}"
  rescue
    fail "Could not build wrapper using Ragel (it failed or not installed?)"
  end
end
