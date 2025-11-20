# long_tail_hey

`long_tail_hey` uses hey to create a stream of requests, and logs its report data, along with Puma data.

The main purpose is to see Puma's behavior when it has more requests than available processing threads.

The number of 'processing threads' is `<number of workers> * <max threads>`.

Current code is set to run several `hey` commands, each increasing the number of connections.
The configuration for each set is done in the `CONNECTION_MULT` array in `benchmarks/local/long_tail_hey.rb`.
Change this array to suite your needs.

A few examples:
```text
benchmarks/local/long_tail_hey.sh     -t5:5 -R100 -d0.2
benchmarks/local/long_tail_hey.sh -w2 -t5:5 -R100 -d0.2
benchmarks/local/long_tail_hey.sh -w4 -t5:5 -R100 -d0.2
```

## Arguments

### Puma

| Arg | Description | Example |
| :-: | ----------- | ------- |
| -t  | Threads     | 5:5     |
| -w  | Workers     | 2       |
| -r  | rackup file | \<path\>|
| -C  | config file | \<path\>|

### Hey

| Arg | Description        | Example |
| :-: | ------------------ | ------- |
| -R  | req per conn       | 100     |
| -k  | disable Keep-Alive | na      |
| -d  | req delay          | float   |

### Ruby

| Arg | Description  |
| :-: | ------------ |
| -Y  | enable YJIT  |

## ENV Settings

| ENV       | Description (Default)                  |
| --------  | -------------------------------------- |
| HEY       | path to hey unless in PATH (hey)       |
| HEY_CPUS  | number of cpu's for hey                |
| PUMA_TEST_HOST4  | IPv4 host (127.0.0.1)           |
| PUMA_TEST_HOST6  | IPv6 host (::1)                 |
| PUMA_TEST_PORT   | port (40001)                    |


## Example Output
```text
$ benchmarks/local/long_tail_hey.sh -w4 -t5:5 -R100 -d0.2

bundle exec exe/puma -q -b tcp://127.0.0.1:40001 -S tmp/bench_test_puma.state -w4 -t5:5 --control-url=tcp://127.0.0.1:40010 --control-token=test test/rackup/sleep.ru

[162886] Puma starting in cluster mode...
[162886] * Puma version: 6.5.0 ("Sky's Version")
[162886] * Ruby version: ruby 3.4.0dev (2024-11-26T17:58:43Z master c1dcd1d496) +PRISM [x86_64-linux]
[162886] *  Min threads: 5
[162886] *  Max threads: 5
[162886] *  Environment: development
[162886] *   Master PID: 162886
[162886] *      Workers: 4
[162886] *     Restarts: (✔) hot (✔) phased
[162886] * Listening on http://127.0.0.1:40001
[162886] Use Ctrl-C to stop
[162886] * Starting control server on http://127.0.0.1:40010
[162886] - Worker 0 (PID: 162895) booted in 0.01s, phase: 0
[162886] - Worker 1 (PID: 162899) booted in 0.01s, phase: 0
[162886] - Worker 2 (PID: 162902) booted in 0.01s, phase: 0
[162886] - Worker 3 (PID: 162906) booted in 0.01s, phase: 0

hey -c  20 -n  2000 -cpus 16  http://127.0.0.1:40001/sleep0.2
hey -c  30 -n  3000 -cpus 16  http://127.0.0.1:40001/sleep0.2
hey -c  40 -n  4000 -cpus 16  http://127.0.0.1:40001/sleep0.2
hey -c  60 -n  6000 -cpus 16  http://127.0.0.1:40001/sleep0.2
hey -c  80 -n  8000 -cpus 16  http://127.0.0.1:40001/sleep0.2


Branch: 00-long-tail-hey Puma: -w4  -t5:5  dly 0.2                                         ─────── Worker Request Info ───────
                         ─────────────────────────── Latency ───────────────────────────    Std        % deviation       Total
Mult/Conn     req/sec      10%     25%     50%     75%     90%     95%     99%    100%      Dev        from 25.00%        Reqs
1.00  20      97.0120    0.2010  0.2018  0.2042  0.2085  0.2098  0.2105  0.2127  0.2186    0.000    0.0  0.0  0.0  0.0    2000
1.50  30      90.7293    0.2060  0.2130  0.2913  0.3983  0.4061  0.4098  0.4141  0.4204    0.935   -3.6 -1.6 -1.1  6.3    3000
2.00  40      96.3451    0.4009  0.4023  0.4074  0.4132  0.4188  0.4507  0.5939  0.6144    0.597   -4.1  0.9  1.4  1.8    4000
3.00  60      96.3643    0.6020  0.6051  0.6109  0.6178  0.6257  0.6396  0.7764  0.8148    0.261   -1.6  0.1  0.1  1.3    6000
4.00  80      95.5128    0.6978  0.8031  0.8117  0.8291  0.9165  0.9970  1.0142  1.2035    0.555   -3.0 -1.2  1.5  2.7    8000

[162886] - Gracefully shutting down workers...
[162886] === puma shutdown: 2024-11-26 13:14:43 -0600 ===
[162886] - Goodbye!

 4:27 Total Time
```
