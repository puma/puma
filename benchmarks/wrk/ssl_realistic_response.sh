bundle exec ruby bin/puma \
                 -t 4 -b "ssl://localhost:9292?key=examples%2Fpuma%2Fpuma_keypair.pem&cert=examples%2Fpuma%2Fcert_puma.pem&verify_mode=none" \
                 test/rackup/realistic_response.ru &
PID1=$!
sleep 5
wrk -c 4 -d 30 --latency https://localhost:9292

kill $PID1
