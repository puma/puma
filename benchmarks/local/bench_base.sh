#!/bin/bash

# -l client threads (loops)
# -c connections per client thread
# -r requests per client
#
# Total connections/requests = l * c * r
#
# -b response body size kB
# -d app delay
#
# -s Puma bind socket type, default ssl, also tcp or unix
# -t Puma threads, default 5:5
# -w Puma workers, default 2
# -r Puma rackup file


export HOST=127.0.0.1
export PORT=40001
export CTRL=40010
export STATE=tmp/bench_test_puma.state

while getopts l:C:c:d:r:R:s:b:T:t:w: option
do
case "${option}"
in
#———————————————————— create_clients options
l) loops=${OPTARG};;
c) connections=${OPTARG};;
r) req_per_client=${OPTARG};;
#———————————————————— Puma options
C) conf=${OPTARG};;
t) threads=${OPTARG};;
w) workers=${OPTARG};;
R) rackup_file=${OPTARG};;
#———————————————————— app/common options
b) body_kb=${OPTARG};;
s) skt_type=${OPTARG};;
d) dly_app=${OPTARG};;
#———————————————————— wrk options
# c (connections) is also used for wrk
T) time=${OPTARG};;
esac
done

optional_args="-S $STATE"

if [ -z "$loops" ] ; then
  loops=10
fi

if [ -z "$connections" ]; then
  connections=0
fi

if [ -z "$time" ] ; then
  time=15
fi

if [ -z "$req_per_client" ]; then
  req_per_client=1
fi

if [ -n "$dly_app" ]; then
  optional_args="$optional_args -d$dly_app"
fi

if [ -n "$body_kb" ]; then
  optional_args="$optional_args -b$body_kb"
  export CI_TEST_KB=$body_kb
fi

if [ -z "$skt_type" ]; then
  skt_type=tcp
fi

puma_args="-S $STATE"

if [ -n "$workers" ]; then
  puma_args="$puma_args -w$workers"
fi

if [ -n "$threads" ]; then
  puma_args="$puma_args -t$threads"
fi

if [ -n "$conf" ]; then
  puma_args="$puma_args -C $conf"
fi

if [ -z "$rackup_file" ]; then
  rackup_file="test/rackup/ci_string.ru"
fi

case $skt_type in
  ssl)
  bind="ssl://$HOST:$PORT?cert=examples/puma/cert_puma.pem&key=examples/puma/puma_keypair.pem&verify_mode=none"
  curl_str=https://$HOST:$PORT
  wrk_str=https://$HOST:$PORT
  ;;
  tcp)
  bind=tcp://$HOST:$PORT
  curl_str=http://$HOST:$PORT
  wrk_str=http://$HOST:$PORT
  ;;
  unix)
  bind=unix://$HOME/skt.unix
  curl_str="--unix-socket $HOME/skt.unix http:/n"
  wrk_str=unix://$HOME/skt.unix
  ;;
  aunix)
  bind=unix://@skt.aunix
  curl_str="--abstract-unix-socket skt.aunix http:/n"
  wrk_str=unix://@skt.aunix
  ;;
esac
