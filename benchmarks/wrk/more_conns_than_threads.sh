bundle exec bin/puma -t 5 test/rackup/hello.ru &
PID1=$!
sleep 5
wrk -c 10 --latency http://localhost:9292

kill $PID1
