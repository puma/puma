#!/bin/bash

# benchmarks/local/long_tail_hey.sh

# see comments in long_tail_hey.rb

source benchmarks/local/bench_base.sh

if [ "$skt_type" == "unix" ] || [ "$skt_type" == "aunix" ]; then
  printf "\nhey doesn't support UNIXSockets...\n\n"
  exit
fi

StartPuma

ruby -I./lib benchmarks/local/long_tail_hey.rb $ruby_args -W $wrk_str
hey_exit=$?

printf "\n"
exit $hey_exit
