bundle exec ruby bin/puma \
                 -t 4 -b "ssl://localhost:9292?keystore=examples/puma/keystore.jks&keystore-pass=blahblah&verify_mode=none" \
                 test/rackup/realistic_response.ru &
PID1=$!
sleep 5
wrk -c 4 -d 30 --latency https://localhost:9292

kill $PID1
