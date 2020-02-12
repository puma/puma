bundle exec bin/puma -t 6 test/rackup/hello.ru &
PID1=$!
sleep 5
wrk -c 12 --latency http://localhost:9292

kill $PID1
