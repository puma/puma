cmd = "ruby -rrubygems -Ilib bin/pumactl -F test/shell/t2_conf.rb -p 0 start"

tcp_port = 0
server = IO.popen(cmd.split(' '))
while (line = server.gets) !~ /Ctrl-C/
  if (port = line[/Listening on tcp:.*:(\d+)/, 1])
    tcp_port = port.to_i
  end
end

`curl -sS http://localhost:#{tcp_port}/`

out=`ruby -rrubygems -Ilib bin/pumactl -F test/shell/t2_conf.rb -p #{tcp_port} status`
`ruby -rrubygems -Ilib bin/pumactl -F test/shell/t2_conf.rb -p #{tcp_port} stop`

Process.wait(server.pid)
log = File.read("t2-stdout")

File.unlink "t2-stdout" if File.file? "t2-stdout"

if log =~ %r(GET / HTTP/1\.1) && !File.file?("t2-pid") && out == "Puma is started\n"
  exit 0
else
  puts "Failed: Log #{log}, t2-pid #{File.file?("t2-pid")}, out #{out}"
  exit 1
end
