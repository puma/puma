# You are encouraged to use @ioquatix's wrk fork, located here: https://github.com/ioquatix/wrk

bundle exec bin/puma -t 5 test/rackup/hello.ru &
PID1=$!
sleep 5
wrk -c 5 --latency http://localhost:9292

kill $PID1
