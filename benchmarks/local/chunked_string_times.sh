#!/bin/sh

# run from Puma directory

# -l client threads (loops)
# -c connections per client thread
# -r requests per client
# Total connections = l * c * r
#
# -s Puma bind socket type, default ssl, also tcp or unix
# -t Puma threads, default 5:5
# -w Puma workers, default 2
#
# example
# benchmarks/local/chunked_string_times.sh -l10 -c100 -r10 -s tcp -t5:5 -w2
#

while getopts l:c:r:s:b:t:w: option
do
case "${option}"
in
l) loops=${OPTARG};;
c) connections=${OPTARG};;
r) req_per_client=${OPTARG};;
s) skt_type=${OPTARG};;
b) body_kb=${OPTARG};;
t) threads=${OPTARG};;
w) workers=${OPTARG};;
esac
done

if test -z "$loops" ; then
  loops=10
fi

if test -z "$connections"; then
  connections=200
fi

if test -z "$req_per_client"; then
  req_per_client=1
fi

if test -z "$skt_type"; then
  skt_type=ssl
fi

if test -z "$threads"; then
  threads=5:5
fi

if test -z "$workers"; then
  workers=2
fi

case $skt_type in
  ssl)
  bind="ssl://127.0.0.1:40010?cert=examples/puma/cert_puma.pem&key=examples/puma/puma_keypair.pem&verify_mode=none"
  curl_str=https://127.0.0.1:40010
  ;;
  tcp)
  bind=tcp://127.0.0.1:40010
  curl_str=http://127.0.0.1:40010
  ;;
  unix)
  bind=unix://$HOME/skt.unix
  curl_str="--unix-socket $HOME/skt.unix http:/n"
  ;;
esac

conf=""

bundle exec ruby -Ilib bin/puma -q -b $bind -t$threads -w$workers $conf --control-url=tcp://127.0.0.1:40001 --control-token=test test/rackup/ci_chunked.ru &
sleep 5s

echo "\n══════════════════════════════════════════════════════════════════════════ Chunked Body"
printf "%7d     1kB Body   ── curl test\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Len: 1' $curl_str)
printf "%7d    10kB Body\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Len: 10' $curl_str)
printf "%7d   100kB Body\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Len: 100' $curl_str)
printf "%7d  2050kB Body\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Len: 2050' $curl_str)

# show headers
# curl -kvo /dev/null -H 'Len: 1' $curl_str

echo "\n────────────────────────────────────────────────────────────────────────────   1kB Body"
ruby ./benchmarks/local/socket_times.rb $loops $connections $req_per_client $skt_type 1

echo "\n────────────────────────────────────────────────────────────────────────────  10kB Body"
ruby benchmarks/local/socket_times.rb $loops $connections $req_per_client $skt_type 10

echo "\n──────────────────────────────────────────────────────────────────────────── 100kB Body"
ruby benchmarks/local/socket_times.rb $loops $connections $req_per_client $skt_type 100

echo "\n─────────────────────────────────────────────────────────────────────────── 2050kB Body"
ruby benchmarks/local/socket_times.rb 10 15 2 $skt_type 2050

echo "\n"
bundle exec ruby -Ilib bin/pumactl -C tcp://127.0.0.1:40001 -T test stop
sleep 3s

echo "\n"

bundle exec ruby -Ilib bin/puma -q -b $bind -t$threads -w$workers $conf --control-url=tcp://127.0.0.1:40001 --control-token=test test/rackup/ci_array.ru &
sleep 5s
echo "\n══════════════════════════════════════════════════════════════════════════   Array Body"
printf "%7d     1kB Body   ── curl test\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Len: 1' $curl_str)
printf "%7d    10kB Body\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Len: 10' $curl_str)
printf "%7d   100kB Body\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Len: 100' $curl_str)
printf "%7d  2050kB Body\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Len: 2050' $curl_str)

# show headers
# curl -kvo /dev/null -H 'Len: 1' $curl_str

echo "\n────────────────────────────────────────────────────────────────────────────   1kB Body"
ruby ./benchmarks/local/socket_times.rb $loops $connections $req_per_client $skt_type 1

echo "\n────────────────────────────────────────────────────────────────────────────  10kB Body"
ruby benchmarks/local/socket_times.rb $loops $connections $req_per_client $skt_type 10

echo "\n──────────────────────────────────────────────────────────────────────────── 100kB Body"
ruby benchmarks/local/socket_times.rb $loops $connections $req_per_client $skt_type 100

echo "\n─────────────────────────────────────────────────────────────────────────── 2050kB Body"
ruby benchmarks/local/socket_times.rb 10 15 2 $skt_type 2050

echo "\n"
bundle exec ruby -Ilib bin/pumactl -C tcp://127.0.0.1:40001 -T test stop
sleep 3s

echo "\n"

bundle exec ruby -Ilib bin/puma -q -b $bind -t$threads -w$workers $conf --control-url=tcp://127.0.0.1:40001 --control-token=test test/rackup/ci_string.ru &
sleep 5s

echo "\n═══════════════════════════════════════════════════════════════════════════ String Body"
printf "%7d     1kB Body   ── curl test\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Len: 1' $curl_str)
printf "%7d    10kB Body\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Len: 10' $curl_str)
printf "%7d   100kB Body\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Len: 100' $curl_str)
printf "%7d  2050kB Body\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Len: 2050' $curl_str)

echo "\n────────────────────────────────────────────────────────────────────────────   1kB Body"
ruby benchmarks/local/socket_times.rb $loops $connections $req_per_client $skt_type 1

echo "\n────────────────────────────────────────────────────────────────────────────  10kB Body"
ruby benchmarks/local/socket_times.rb $loops $connections $req_per_client $skt_type 10

echo "\n──────────────────────────────────────────────────────────────────────────── 100kB Body"
ruby benchmarks/local/socket_times.rb $loops $connections $req_per_client $skt_type 100

echo "\n─────────────────────────────────────────────────────────────────────────── 2050kB Body"
ruby benchmarks/local/socket_times.rb 10 15 2 $skt_type 2050

echo "\n"
bundle exec ruby -Ilib bin/pumactl -C tcp://127.0.0.1:40001 -T test stop
sleep 3
