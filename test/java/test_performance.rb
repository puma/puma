require 'http11'

include Mongrel

def one_test(pr)
  req = {}
  http = "GET / HTTP/1.1\r\n\r\n"
  nread = pr.execute(req, http, 0)
  pr.reset
end

parser = HttpParser.new

before = Time.now
for n in (1..100000)
  one_test(parser)
end
after = Time.now

puts "Doing 100000 parses took #{after-before} seconds"

