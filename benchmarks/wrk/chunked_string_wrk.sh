#!/bin/sh

# run from Puma directory

# -s Puma bind socket type, default ssl, also tcp or unix
# -t Puma threads, default 5:5
# -w Puma workers, default 2
#
# Test uses 4 curl connections for workers 0 or 1, and 8 curl connections for
# workers two or more.

# example
# benchmarks/wrk/chunked_string_wrk.sh -s tcp -t5:5 -w2
#

while getopts s:t:w: option
do
case "${option}"
in
s) skt_type=${OPTARG};;
t) threads=${OPTARG};;
w) workers=${OPTARG};;
esac
done

if test -z "$skt_type"; then
  skt_type=ssl
fi

if test -z "$threads"; then
  threads=5:5
fi

if test -z "$workers"; then
  workers=2
fi

if [ $workers -gt 1 ]; then
  wrk_c=8
else
  wrk_c=4
fi

wrk_t=2

case $skt_type in
  ssl)
  bind="ssl://127.0.0.1:40010?cert=examples/puma/cert_puma.pem&key=examples/puma/puma_keypair.pem&verify_mode=none"
  wrk_url=https://127.0.0.1:40010
  ;;
  tcp)
  bind=tcp://127.0.0.1:40010
  wrk_url=http://127.0.0.1:40010
  ;;
  unix)
  bind=unix://$HOME/skt.unix
  echo UNIXSockets unvailable with wrk
  exit
  ;;
esac

conf=""
echo bundle exec ruby -Ilib bin/puma -q -b $bind -t$threads -w$workers $conf --control-url=tcp://127.0.0.1:40001 --control-token=test test/rackup/ci_chunked.ru
bundle exec ruby -Ilib bin/puma -q -b $bind -t$threads -w$workers $conf --control-url=tcp://127.0.0.1:40001 --control-token=test test/rackup/ci_chunked.ru &
sleep 5s

echo "\n══════════════════════════════════════════════════════════════════════════ Chunked Body"

echo "\n────────────────────────────────────────────────────────────────────────────   1kB Body"
wrk -c $wrk_c -t $wrk_t -d 20 --latency -H 'Len: 1' $wrk_url

echo "\n────────────────────────────────────────────────────────────────────────────  10kB Body"
wrk -c $wrk_c -t $wrk_t -d 20 --latency -H 'Len: 10' $wrk_url

echo "\n──────────────────────────────────────────────────────────────────────────── 100kB Body"
wrk -c $wrk_c -t $wrk_t -d 20 --latency -H 'Len: 100' $wrk_url

echo "\n"
bundle exec ruby -Ilib bin/pumactl -C tcp://127.0.0.1:40001 -T test stop
sleep 3s

echo "\n"
bundle exec ruby -Ilib bin/puma -q -b $bind -t$threads -w$workers $conf --control-url=tcp://127.0.0.1:40001 --control-token=test test/rackup/ci_string.ru &

sleep 5s

echo "\n═══════════════════════════════════════════════════════════════════════════ String Body"

echo "\n────────────────────────────────────────────────────────────────────────────   1kB Body"
wrk -c $wrk_c -t $wrk_t -d 20 --latency $wr_url -H 'Len: 1' $wrk_url

echo "\n────────────────────────────────────────────────────────────────────────────  10kB Body"
wrk -c $wrk_c -t $wrk_t -d 20 --latency $wr_url -H 'Len: 10' $wrk_url

echo "\n──────────────────────────────────────────────────────────────────────────── 100kB Body"
wrk -c $wrk_c -t $wrk_t -d 20 --latency $wr_url -H 'Len: 100' $wrk_url

echo "\n"
bundle exec ruby -Ilib bin/pumactl -C tcp://127.0.0.1:40001 -T test stop
sleep 3

# echo "\n──────────────────────────────────────────────────────────────────────────── netstat -ant"
# netstat -ant
