# the following is a benchmark script specifically for JRuby & testing OpenSSL vs Java JDK Engine
# to flip between the true, simply change `puma.ssl.use-netty` [true|false] accordingly.
#
# Previous results on a Macbook:
#      Processor Speed: 2.6 GHz
#      Number of Processors: 1
#      Total Number of Cores: 6
#      Memory: 16 GB
#
# JDK Engine
#   2 threads and 4 connections
#  Thread Stats   Avg      Stdev     Max   +/- Stdev
#    Latency     3.58ms    2.47ms  87.61ms   98.72%
#    Req/Sec   580.07     62.48   666.00     90.30%
#  Latency Distribution
#     50%    3.31ms
#     75%    3.49ms
#     90%    3.85ms
#     99%    6.44ms
#  34553 requests in 30.10s, 6.49GB read
# Requests/sec:   1147.91
# Transfer/sec:    220.86MB
#
# OpenSSL engine
#
#  Thread Stats   Avg      Stdev     Max   +/- Stdev
#    Latency    14.71ms   27.64ms 149.69ms   83.57%
#    Req/Sec     2.54k     1.01k    4.97k    69.00%
#  Latency Distribution
#     50%  477.00us
#     75%   11.29ms
#     90%   65.76ms
#     99%   98.47ms
#  151625 requests in 30.07s, 28.49GB read
# Requests/sec:   5042.61
# Transfer/sec:      0.95GB
CLASSPATH=tmp/java/puma_http11/netty-buffer-4.1.47.Final.jar:tmp/java/puma_http11/netty-handler-4.1.47.Final.jar:tmp/java/puma_http11/netty-common-4.1.47.Final.jar:tmp/java/puma_http11/netty-codec-4.1.47.Final.jar:tmp/java/puma_http11/netty-tcnative-boringssl-static-2.0.29.Final.jar \
 bundle exec ruby -J-Djava.util.logging.config.file=logging.properties -J-Dpuma.ssl.use-netty=true \
            bin/puma \
            -t 4 -b "ssl://localhost:9292?keystore=examples%2Fpuma%2Fkeystore.jks&keystore-pass=blahblah&verify_mode=none" test/rackup/realistic_response.ru &
PID1=$!
sleep 5
wrk -c 4 -d 30 --latency https://localhost:9292

kill $PID1
