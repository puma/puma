#!/usr/bin/env bash

# Compares Puma's C HTTP parser with the pure Ruby one, Puma::RubyHttpParser,
# end to end: requests per second for a minimal GET and for a browser-like GET
# with 17 headers, served by test/rackup/hello.ru.
#
#   benchmarks/wrk/http_parser.sh [rounds]
#
# Each run starts a fresh single-mode Puma, warms it up with wrk for 10 s and
# then measures for 20 s. The parsers take turns within each round, so a change
# in the machine's load falls on both. Three rounds take about 7 minutes.
#
# YJIT is on unless RUBYOPT is set. RUBYOPT= runs without it. PORT changes the
# port, 9292 by default.
#
# The browser request's path and headers are those of BROWSER_GET in
# benchmarks/local/http_parser.rb, except Host, which wrk sends itself.

cd "$(dirname "$0")/../.." || exit 1

rounds=${1:-3}
port=${PORT:-9292}
export RUBYOPT=${RUBYOPT---yjit}

browser_path='/products/42?ref=home&utm_source=newsletter'
browser_headers=(
  'Connection: keep-alive'
  'sec-ch-ua: "Chromium";v="130", "Google Chrome";v="130", "Not?A_Brand";v="99"'
  'sec-ch-ua-mobile: ?0'
  'sec-ch-ua-platform: "macOS"'
  'Upgrade-Insecure-Requests: 1'
  'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'
  'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7'
  'Sec-Fetch-Site: same-origin'
  'Sec-Fetch-Mode: navigate'
  'Sec-Fetch-User: ?1'
  'Sec-Fetch-Dest: document'
  'Referer: https://www.example.com/products?page=2'
  'Accept-Encoding: gzip, deflate, br, zstd'
  'Accept-Language: en-AU,en-GB;q=0.9,en;q=0.8'
  'Cookie: _ga=GA1.1.1234567890.1700000000; _example_session=3f2a9c1e8b7d4a6f0e5c2b1a9d8c7e6f5a4b3c2d1e0f9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e0f; theme=dark; locale=en-AU'
  'If-None-Match: W/"5d41402abc4b2a76b9719d911017c592"'
)

command -v wrk > /dev/null || { echo "This needs wrk: https://github.com/wg/wrk" >&2; exit 1; }
if ! bundle exec ruby -Ilib -rpuma -e 'exit 1 unless defined?(Puma::NativeHttpParser)' 2> /dev/null; then
  echo "Puma's C extension isn't loaded, so there's nothing to compare against. Build it with: bundle exec rake compile" >&2
  exit 1
fi

listening() { (: < "/dev/tcp/127.0.0.1/$port") 2> /dev/null; }

if listening; then
  echo "Something is already listening on port $port. Choose another with PORT." >&2
  exit 1
fi

pid=
results=$(mktemp)
stop_puma() { [ -n "$pid" ] && kill "$pid" 2> /dev/null && wait "$pid" 2> /dev/null; pid=; }
trap 'stop_puma; rm -f "$results"' EXIT

# Runs one parser on one request, and prints a line of results.
run() {
  local round=$1 request=$2 parser=$3 url="http://127.0.0.1:$port/" pure= args=() h out
  if [ "$request" = browser ]; then
    url="http://127.0.0.1:$port$browser_path"
    for h in "${browser_headers[@]}"; do args+=(-H "$h"); done
  fi
  [ "$parser" = Ruby ] && pure=1

  PUMA_PURE_RUBY_PARSER=$pure bundle exec bin/puma -t 4:4 -b "tcp://127.0.0.1:$port" -q test/rackup/hello.ru > /dev/null &
  pid=$!
  for _ in $(seq 100); do listening && break; sleep 0.1; done
  listening || { echo "Puma didn't start on port $port" >&2; exit 1; }

  wrk -t 4 -c 16 -d 10s "${args[@]}" "$url" > /dev/null
  out=$(wrk -t 4 -c 16 -d 20s --latency "${args[@]}" "$url")
  stop_puma

  # A request the parser rejects gets a 400, so these should be 0.
  local rps p99 bad
  rps=$(awk '/^Requests\/sec:/ { print $2 }' <<< "$out")
  [ -n "$rps" ] || { printf 'wrk failed:\n%s\n' "$out" >&2; exit 1; }
  p99=$(awk '$1 == "99%" { print $2 }' <<< "$out")
  bad=$(awk '/Non-2xx or 3xx responses:/ { print $NF }' <<< "$out")
  printf '%-6s %-8s %-5s %11.0f %10s %8s\n' "$round" "$request" "$parser" "$rps" "$p99" "${bad:-0}"
  echo "$request $parser $rps" >> "$results"
}

median() {
  awk -v req="$1" -v parser="$2" '$1 == req && $2 == parser { print $3 }' "$results" | sort -n |
    awk '{ v[NR] = $1 } END { print (NR % 2) ? v[(NR + 1) / 2] : (v[NR / 2] + v[NR / 2 + 1]) / 2 }'
}

echo "$(bundle exec ruby -e 'print RUBY_DESCRIPTION'), RUBYOPT=$RUBYOPT"
printf '%-6s %-8s %-5s %11s %10s %8s\n' round request parser req/s "p99" non-2xx
for round in $(seq "$rounds"); do
  for request in minimal browser; do
    # Alternate which parser goes first.
    if [ $((round % 2)) = 1 ]; then order="C Ruby"; else order="Ruby C"; fi
    for parser in $order; do run "$round" "$request" "$parser"; done
  done
done

echo
echo "Medians:"
for request in minimal browser; do
  c=$(median "$request" C)
  ruby=$(median "$request" Ruby)
  awk -v req="$request" -v c="$c" -v r="$ruby" \
    'BEGIN { printf "%-8s C %8.0f req/s   Ruby %8.0f req/s   Ruby/C %.2f\n", req, c, r, r / c }'
done
