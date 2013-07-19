system "ruby -rubygems -I../../lib ../../bin/puma -p 10102 -C t1_conf.rb ../hello.ru &"
sleep 5
system "curl http://localhost:10102/"

system "kill `cat t1-pid`"

sleep 1

log = File.read("t1-stdout")

File.unlink "t1-stdout" if File.file? "t1-stdout"
File.unlink "t1-pid" if File.file? "t1-pid"

if log =~ %r!GET / HTTP/1\.1!
  exit 0
else
  exit 1
end

