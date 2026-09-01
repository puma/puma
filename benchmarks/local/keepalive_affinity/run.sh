#!/usr/bin/env bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../../.." && pwd )"
cd "$PROJECT_ROOT"

export PUMA_BENCH_PORT=${PUMA_BENCH_PORT:-9292}
PIDFILE="tmp/keepalive_affinity.pid"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

cleanup() {
    echo -e "${YELLOW}Cleaning up...${NC}"
    if [ -f "$PIDFILE" ]; then
        PID=$(cat "$PIDFILE")
        if kill -0 "$PID" 2>/dev/null; then
            kill "$PID" 2>/dev/null || true
            sleep 2
            kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null || true
        fi
        rm -f "$PIDFILE"
    fi
}

trap cleanup EXIT
mkdir -p tmp

echo -e "${GREEN}Starting Puma (2 workers, 1 thread each, port $PUMA_BENCH_PORT)...${NC}"
bundle exec ruby -Ilib bin/puma \
  -C "$SCRIPT_DIR/puma_config.rb" \
  --pidfile "$PIDFILE" \
  -q \
  "$SCRIPT_DIR/config.ru" &

PUMA_PID=$!
echo "Puma master PID: $PUMA_PID"

echo -e "${YELLOW}Waiting for Puma to start...${NC}"
for i in $(seq 1 30); do
    if curl -sf "http://127.0.0.1:$PUMA_BENCH_PORT/pid" > /dev/null 2>&1; then
        echo -e "${GREEN}Puma is ready.${NC}"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo -e "${RED}Puma failed to start within 30 seconds.${NC}"
        exit 1
    fi
    sleep 1
done

# Let workers fully boot
sleep 2

echo ""
ruby -Ilib "$SCRIPT_DIR/client.rb" \
  --port "$PUMA_BENCH_PORT" \
  --extra-conns "${EXTRA_CONNS:-4}" \
  --rounds "${ROUNDS:-20}" \
  "$@"
