# You are encouraged to use @ioquatix's wrk fork, located here: https://github.com/ioquatix/wrk

benchmark() {
  bundle exec bin/puma -t 4 test/rackup/hello.ru &
  PID1=$!
  sleep 5
  echo "Warming up YJIT"
  wrk -c 4 -d 30 --latency http://localhost:9292 > /dev/null
  echo "Running"
  wrk -c 16 -t 8 -d 30 --latency http://localhost:9292
  kill $PID1
}

export RUBY_YJIT_ENABLE=1

echo "===================================="
echo "C parser"
echo "===================================="

unset PUMA_PURE_RUBY_PARSER
rake clean
rake compile
benchmark

echo "===================================="
echo "Ruby parser"
echo "===================================="

rake clean
export PUMA_PURE_RUBY_PARSER=1
rake compile
benchmark
