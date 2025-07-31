#!/bin/bash

# bundle exec bin/puma -q -b tcp://127.0.0.1:40001 -w4 -t5:5 --pidfile pid -C test/config/fork_worker.rb test/rackup/sleep.ru

# ./benchmarks/local/refork.sh

PID=$(cat pid)

HEY_C=25
HEY_N=20000
HEY_CPU=10
SLP_DLY=0.01

hey -c $HEY_C -n $HEY_N -cpus $HEY_CPU  http://127.0.0.1:40001/sleep$SLP_DLY
echo ──────────────────────────────────────────────────────────────────────────────────────────────────── 0
kill -SIGURG $PID
sleep 1.5
hey -c $HEY_C -n $HEY_N -cpus $HEY_CPU  http://127.0.0.1:40001/sleep$SLP_DLY
echo ──────────────────────────────────────────────────────────────────────────────────────────────────── 1
kill -SIGURG $PID
sleep 1.5
hey -c $HEY_C -n $HEY_N -cpus $HEY_CPU  http://127.0.0.1:40001/sleep$SLP_DLY
echo ──────────────────────────────────────────────────────────────────────────────────────────────────── 2
kill -SIGURG $PID
sleep 1.5
hey -c $HEY_C -n $HEY_N -cpus $HEY_CPU  http://127.0.0.1:40001/sleep$SLP_DLY
echo ──────────────────────────────────────────────────────────────────────────────────────────────────── 3
kill -SIGURG $PID
sleep 1.5
hey -c $HEY_C -n $HEY_N -cpus $HEY_CPU  http://127.0.0.1:40001/sleep$SLP_DLY
echo ──────────────────────────────────────────────────────────────────────────────────────────────────── 4
