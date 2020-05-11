#!/bin/bash

set -eo pipefail

ITERATIONS=400000
HOST=127.0.0.1:9292
URL="http://$HOST/cpu/$ITERATIONS"

MIN_WORKERS=1
MAX_WORKERS=4

MIN_THREADS=4
MAX_THREADS=4

DURATION=2
MIN_CONCURRENT=1
MAX_CONCURRENT=8

retry() {
  local tries="$1"
  local sleep="$2"
  shift 2

  for i in $(seq 1 $tries); do
    if eval "$@"; then
      return 0
    fi

    sleep "$sleep"
  done

  return 1
}

ms() {
  VALUE=$(cat)
  FRAC=${VALUE%%[ums]*}
  case "$VALUE" in
    *us)
      echo "scale=1; ${FRAC}/1000" | bc
      ;;

    *ms)
      echo "scale=1; ${FRAC}/1" | bc
      ;;

    *s)
      echo "scale=1; ${FRAC}*1000/1" | bc
      ;;
  esac
}

run_wrk() {
  mkdir tmp &>/dev/null || true
  result=$(wrk -H "Connection: Close" -c "$wrk_c" -t "$wrk_t" -d "$DURATION" --latency "$@" | tee -a tmp/wrk.txt)
  req_sec=$(echo "$result" | grep "^Requests/sec:" | awk '{print $2}')
  latency_avg=$(echo "$result" | grep "^\s*Latency.*%" | awk '{print $2}' | ms)
  latency_stddev=$(echo "$result" | grep "^\s*Latency.*%" | awk '{print $3}' | ms)
  latency_50=$(echo "$result" | grep "^\s*50%" | awk '{print $2}' | ms)
  latency_75=$(echo "$result" | grep "^\s*75%" | awk '{print $2}' | ms)
  latency_90=$(echo "$result" | grep "^\s*90%" | awk '{print $2}' | ms)
  latency_99=$(echo "$result" | grep "^\s*99%" | awk '{print $2}' | ms)

  echo -e "$workers\t$threads\t$wrk_c\t$wrk_t\t$req_sec\t$latency_avg\t$latency_stddev\t$latency_50\t$latency_75\t$latency_90\t$latency_99"
}

run_concurrency_tests() {
  echo
  echo -e "PUMA_W\tPUMA_T\tWRK_C\tWRK_T\tREQ_SEC\tL_AVG\tL_DEV\tL_50%\tL_75%\tL_90%\tL_99%"
  for wrk_c in $(seq $MIN_CONCURRENT $MAX_CONCURRENT); do
    wrk_t="$wrk_c"
    eval "$@"
    sleep 1
  done
  echo
}

with_puma() {
  # start puma and wait for 10s for it to start
  bundle exec bin/puma -w "$workers" -t "$threads" -b "tcp://$HOST" -C test/config/cpu_spin.rb &
  local puma_pid=$!
  trap "kill $puma_pid" EXIT

  # wait for Puma to be up
  if ! retry 10 1s curl --fail "$URL" &>/dev/null; then
    echo "Failed to connect to $URL."
    return 1
  fi

  # execute testing command
  eval "$@"
  kill "$puma_pid" || true
  trap - EXIT
  wait
}

for workers in $(seq $MIN_WORKERS $MAX_WORKERS); do
  for threads in $(seq $MIN_THREADS $MAX_THREADS); do
    with_puma \
      run_concurrency_tests \
      run_wrk "$URL"
  done
done
