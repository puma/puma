bundle exec bin/puma -t 4 test/rackup/many_long_headers.ru &
PID1=$!
sleep 5
wrk -c 4 -d 30 --latency http://localhost:9292

kill $PID1
