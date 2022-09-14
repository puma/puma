#!/bin/bash

# see comments in response_time_wrk.rb

source benchmarks/local/bench_base.sh

if [ "$skt_type" == "unix" ] || [ "$skt_type" == "aunix" ]; then
  printf "\nwrk doesn't support UNIXSockets...\n\n"
  exit
fi

StartPuma

ruby -I./lib benchmarks/local/response_time_wrk.rb $ruby_args -W $wrk_str
wrk_exit=$?

printf "\n"
exit $wrk_exit
