#!/usr/bin/env bash

# benchmarks/local/long_tail_hey-0-2-4-8.sh
#
# -d app delay, default 0.010
# -t Threads, default 3:3
# -c hey requests per connection, default 100
#
# see comments in long_tail_hey.rb

while getopts :b:C:c:d:kR:r:s:T:t:w:Y option
do
case "${option}" in
#———————————————————— RUBY options
Y) export RUBYOPT=--yjit;;
#———————————————————— Puma options
C) conf=${OPTARG};;
t) THREADS=${OPTARG};;
#———————————————————— app/common options
d) DLY=${OPTARG};;
#———————————————————— wrk options
c) REQS_PER_CONN=${OPTARG};;
?) echo "Error: Invalid option was specified -$OPTARG"; exit;;
esac
done

if [[ -z "$THREADS" ]]; then
  THREADS=3:3
fi

if [[ -z "$REQS_PER_CONN" ]]; then
  REQS_PER_CONN=100
fi

if [[ -z "$DLY" ]]; then
  DLY=0.010
fi

SECONDS=0

benchmarks/local/long_tail_hey.sh -w8 -t$THREADS -R$REQS_PER_CONN -d$DLY
sleep 2s
benchmarks/local/long_tail_hey.sh -w4 -t$THREADS -R$REQS_PER_CONN -d$DLY
sleep 2s
benchmarks/local/long_tail_hey.sh -w2 -t$THREADS -R$REQS_PER_CONN -d$DLY
sleep 2s
benchmarks/local/long_tail_hey.sh     -t$THREADS -R$REQS_PER_CONN -d$DLY
sleep 2s
# disable keep-alive
benchmarks/local/long_tail_hey.sh -w8 -t$THREADS -R$REQS_PER_CONN -d$DLY -k
sleep 2s
benchmarks/local/long_tail_hey.sh -w4 -t$THREADS -R$REQS_PER_CONN -d$DLY -k
sleep 2s
benchmarks/local/long_tail_hey.sh -w2 -t$THREADS -R$REQS_PER_CONN -d$DLY -k
sleep 2s
benchmarks/local/long_tail_hey.sh     -t$THREADS -R$REQS_PER_CONN -d$DLY -k
sleep 2s

TZ=UTC0 printf '\n%(%H:%M:%S)T All Total Time\n' $SECONDS
