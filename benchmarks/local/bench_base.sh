#!/bin/bash

# -T client threads (wrk -t)
# -c connections per client thread
# -R requests per client
#
# Total connections/requests = l * c * r
#
# -b response body size kB
# -d app delay
#
# -s Puma bind socket type, default ssl, also tcp or unix
# -t Puma threads
# -w Puma workers
# -r Puma rackup file

if [[ "$@" =~ ^[^-].* ]]; then
  echo "Error: Invalid option was specified $1"
  exit
fi

PUMA_BENCH_CMD=$0
PUMA_BENCH_ARGS=$@

export PUMA_BENCH_CMD
export PUMA_BENCH_ARGS

if [ -z "$PUMA_TEST_HOST4" ]; then export PUMA_TEST_HOST4=127.0.0.1; fi
if [ -z "$PUMA_TEST_HOST6" ]; then export PUMA_TEST_HOST6=::1;       fi
if [ -z "$PUMA_TEST_PORT"  ]; then export PUMA_TEST_PORT=40001;      fi
if [ -z "$PUMA_TEST_CTRL"  ]; then export PUMA_TEST_CTRL=40010;      fi
if [ -z "$PUMA_TEST_STATE" ]; then export PUMA_TEST_STATE=tmp/bench_test_puma.state; fi

export PUMA_CTRL=$PUMA_TEST_HOST4:$PUMA_TEST_CTRL

while getopts :b:C:c:D:d:kR:r:s:T:t:w:Y option
do
case "${option}" in
#———————————————————— RUBY options
Y) export RUBYOPT=--yjit;;
#———————————————————— Puma options
C) conf=${OPTARG};;
t) threads=${OPTARG};;
w) workers=${OPTARG};;
r) rackup_file=${OPTARG};;
#———————————————————— app/common options
b) body_conf=${OPTARG};;
s) skt_type=${OPTARG};;
d) dly_app=${OPTARG};;
#———————————————————— request_stream options
T) stream_threads=${OPTARG};;
D) duration=${OPTARG};;
R) req_per_socket=${OPTARG};;
#———————————————————— wrk options
c) connections=${OPTARG};;
# T) stream_threads=${OPTARG};;
# D) duration=${OPTARG};;
#———————————————————— hey options
k) disable_keepalive=true;;
?) echo "Error: Invalid option was specified -$OPTARG"; exit;;
esac
done

# -n not empty, -z is empty

ruby_args="-S $PUMA_TEST_STATE"

if [ -n "$connections" ]; then
  ruby_args="$ruby_args -c$connections"
fi

if [ -n "$stream_threads" ]; then
  ruby_args="$ruby_args -T$stream_threads"
fi

if [ -n "$duration" ] ; then
  ruby_args="$ruby_args -D$duration"
fi

if [ -n "$req_per_socket" ]; then
  ruby_args="$ruby_args -R$req_per_socket"
fi

if [ -n "$dly_app" ]; then
  ruby_args="$ruby_args -d$dly_app"
fi

if [ -n "$body_conf" ]; then
  ruby_args="$ruby_args -b $body_conf"
  export CI_BODY_CONF=$body_conf
fi

if [ -z "$skt_type" ]; then
  skt_type=tcp
fi

ruby_args="$ruby_args -s $skt_type"

puma_args="-S $PUMA_TEST_STATE"

if [ -n "$workers" ]; then
  puma_args="$puma_args -w$workers"
  ruby_args="$ruby_args -w$workers"
fi


if [ -n "$disable_keepalive" ]; then
  ruby_args="$ruby_args -k"
fi

if [ -z "$threads" ]; then
  threads=0:5
fi

puma_args="$puma_args -t$threads"
ruby_args="$ruby_args -t$threads"

if [ -n "$conf" ]; then
  puma_args="$puma_args -C $conf"
fi

if [ -z "$rackup_file" ]; then
  rackup_file="test/rackup/sleep.ru"
fi

ip4=$PUMA_TEST_HOST4:$PUMA_TEST_PORT
ip6=[$PUMA_TEST_HOST6]:$PUMA_TEST_PORT

case $skt_type in
  ssl4)
  bind="ssl://$PUMA_TEST_HOST4:$PUMA_TEST_PORT?cert=examples/puma/cert_puma.pem&key=examples/puma/puma_keypair.pem&verify_mode=none"
  curl_str=https://$ip4
  wrk_str=https://$ip4
  ;;
  ssl)
  bind="ssl://$ip4?cert=examples/puma/cert_puma.pem&key=examples/puma/puma_keypair.pem&verify_mode=none"
  curl_str=https://$ip4
  wrk_str=https://$ip4
  ;;
  ssl6)
  bind="ssl://$ip6?cert=examples/puma/cert_puma.pem&key=examples/puma/puma_keypair.pem&verify_mode=none"
  curl_str=https://$ip6
  wrk_str=https://$ip6
  ;;
  tcp4)
  bind=tcp://$ip4
  curl_str=http://$ip4
  wrk_str=http://$ip4
  ;;
  tcp)
  bind=tcp://$ip4
  curl_str=http://$ip4
  wrk_str=http://$ip4
  ;;
  tcp6)
  bind=tcp://$ip6
  curl_str=http://$ip6
  wrk_str=http://$ip6
  ;;
  unix)
  bind=unix://tmp/benchmark_skt.unix
  curl_str="--unix-socket tmp/benchmark_skt.unix http:/n"
  ;;
  aunix)
  bind=unix://@benchmark_skt.aunix
  curl_str="--abstract-unix-socket benchmark_skt.aunix http:/n"
  ;;
  *)
  echo "Error: Invalid socket type option was specified '$skt_type'"
  exit
  ;;
esac

StartPuma()
{
  if [ -n "$1" ]; then
    rackup_file=$1
  fi
  printf "\nbundle exec bin/puma -q -b $bind $puma_args --control-url=tcp://$PUMA_CTRL --control-token=test $rackup_file\n\n"
  bundle exec bin/puma -q -b $bind $puma_args --control-url=tcp://$PUMA_CTRL --control-token=test $rackup_file &
  sleep 1s
}
