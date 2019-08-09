system "ruby -rrubygems -Ilib bin/pumactl -F test/shell/t2_conf.rb start"
sleep 5
system "curl http://localhost:10103/"

out=`ruby -rrubygems -Ilib bin/pumactl -F test/shell/t2_conf.rb status`

system "ruby -rrubygems -Ilib bin/pumactl -F test/shell/t2_conf.rb stop"

sleep 1

log = File.read("t2-stdout")

File.unlink "t2-stdout" if File.file? "t2-stdout"

if log =~ %r(GET / HTTP/1\.1) && !File.file?("t2-pid") && out == "Puma is started\n"
  exit 0
else
  exit 1
end
