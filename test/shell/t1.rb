tcp_port = 0
cmd = "ruby -rrubygems -Ilib bin/puma -p #{tcp_port} -C test/shell/t1_conf.rb test/rackup/hello.ru"
server = IO.popen(cmd.split(' '))

while (line = server.gets) !~ /Ctrl-C/
  if (port = line[/Listening on tcp:.*:(\d+)/, 1])
    tcp_port = port.to_i
  end
end
`curl -sS http://localhost:#{tcp_port}/`

Process.kill :TERM, server.pid
Process.wait(server.pid)

log = File.read("t1-stdout")

File.unlink "t1-stdout" if File.file? "t1-stdout"
File.unlink "t1-pid" if File.file? "t1-pid"

if log =~ %r!GET / HTTP/1\.1!
  exit 0
else
  puts "Failed, log #{log}"
  exit 1
end
