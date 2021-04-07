# You are encouraged to use @ioquatix's wrk fork,
# located here: https://github.com/ioquatix/wrk

# two args, 1st is ru file, 2nd is length when used with ci_chunked.ru or
# ci_string.ru, defaults to 10 in the ru files
# Examples
#   benchmarks/wrk/ci_length.sh ci_chunked.ru 100      chunked 100 kb body
#   benchmarks/wrk/ci_length.sh ci_string.ru 10        string   10 kb body

ru="test/rackup/$1"

if [ -n "$2" ]; then
export CI_TEST_KB="$2"
fi

bundle exec bin/puma -t 4 $ru &
PID1=$!
sleep 5
wrk -c 4 -d 30 --latency http://localhost:9292

kill $PID1
