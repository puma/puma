system "ruby -rrubygems -Ilib bin/pumactl -F test/shell/t2_conf.rb start"
sleep 5
system "curl http://localhost:10103/"

system "ruby -rrubygems -Ilib bin/pumactl -F test/shell/t2_conf.rb stop"

sleep 1

log = File.read("t2-stdout")

File.unlink "t2-stdout" if File.file? "t2-stdout"

if log =~ %r(GET / HTTP/1\.1) && !File.file?("t2-pid")
  exit 0
else
  exit 1
end
