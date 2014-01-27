system "ruby -rubygems -I../../lib ../../bin/puma -p 10102 -C t3_conf.rb ../hello.ru &"
sleep 5

worker_pid_was_present = File.file? "t3-worker-2-pid"

system "kill `cat t3-worker-2-pid`" # kill off a worker

sleep 2

worker_index_within_number_of_workers = !File.file?("t3-worker-3-pid")

system "kill `cat t3-pid`" 

File.unlink "t3-pid" if File.file? "t3-pid"
File.unlink "t3-worker-0-pid" if File.file? "t3-worker-0-pid"
File.unlink "t3-worker-1-pid" if File.file? "t3-worker-1-pid"
File.unlink "t3-worker-2-pid" if File.file? "t3-worker-2-pid"
File.unlink "t3-worker-3-pid" if File.file? "t3-worker-3-pid"

if worker_pid_was_present and worker_index_within_number_of_workers
  exit 0
else
  exit 1
end

