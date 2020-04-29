cmd = "ruby -rrubygems -Ilib bin/puma -p 0 -C test/shell/t3_conf.rb test/rackup/hello.ru"
server = IO.popen(cmd.split(' '))

worker2 = 't3-worker-2-pid'
sleep 0.1 until File.file? worker2

worker_pid_was_present = File.file? worker2

pid = File.read(worker2).to_i
File.unlink(worker2)
Process.kill :TERM, pid # kill off a worker

sleep 0.1 until File.file? worker2

worker_index_within_number_of_workers = !File.file?("t3-worker-3-pid")

main_pid = Integer(File.read("t3-pid"))
Process.kill :TERM, main_pid
Process.wait server.pid

File.unlink "t3-pid" if File.file? "t3-pid"
File.unlink "t3-worker-0-pid" if File.file? "t3-worker-0-pid"
File.unlink "t3-worker-1-pid" if File.file? "t3-worker-1-pid"
File.unlink "t3-worker-2-pid" if File.file? "t3-worker-2-pid"
File.unlink "t3-worker-3-pid" if File.file? "t3-worker-3-pid"

if worker_pid_was_present and worker_index_within_number_of_workers
  exit 0
else
  puts "Failed: #{worker_pid_was_present} #{worker_index_within_number_of_workers}"
  exit 1
end
