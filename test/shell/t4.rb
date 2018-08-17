system "rm test/log.log*"

system "ruby -rrubygems -Ilib bin/pumactl -F test/shell/t4_conf.rb start"
sleep 5
worker_pid = `ps aux | grep puma | grep worker`.split[1]

system "curl http://localhost:10104"
system "mv test/log.log test/log.log.1"
system "ps aux | grep puma"
system "kill -HUP `cat t4-pid`"
sleep 8

system "echo 'exec request 8s'"
system "curl http://localhost:10104"
sleep 1

system "ruby -rrubygems -Ilib bin/pumactl -F test/shell/t4_conf.rb stop"

def cleanup
  system "rm test/log.log*"
  system "rm t4-stdout"
  system "rm t4-stderr"
end

if `ps aux | grep puma | grep worker`.split[1] != worker_pid
  cleanup
  puts "worker pid changed"
  exit 1
end

if File.size("test/log.log") == 0
  cleanup
  puts "nothing written to reopened log file"
  exit 1
end

cleanup
exit 0
