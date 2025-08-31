#!/bin/bash

# Exit on any error
set -e

# Configuration
PUMA_CMD="bundle exec ruby -Ilib bin/puma -w1 -t1 --pidfile tmp/pidfile test/rackup/hello.ru"
WRK_CMD="wrk -t 6 -c 12 -d 10s http://localhost:9292"
PIDFILE="tmp/pidfile"
PORT=9292

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to cleanup on exit
cleanup() {
    echo -e "${YELLOW}Cleaning up...${NC}"
    if [ -f "$PIDFILE" ]; then
        PID=$(cat "$PIDFILE")
        if kill -0 "$PID" 2>/dev/null; then
            echo -e "${YELLOW}Killing Puma process (PID: $PID)${NC}"
            kill "$PID"
            # Wait a bit for graceful shutdown
            sleep 2
            # Force kill if still running
            if kill -0 "$PID" 2>/dev/null; then
                echo -e "${RED}Force killing Puma process${NC}"
                kill -9 "$PID"
            fi
        fi
        rm -f "$PIDFILE"
    fi
    echo -e "${GREEN}Cleanup complete${NC}"
}

# Set up trap to cleanup on script exit
trap cleanup EXIT

# Ensure tmp directory exists
mkdir -p tmp

# Start Puma in background
echo -e "${GREEN}Starting Puma...${NC}"
echo "Command: $PUMA_CMD"
$PUMA_CMD &
PUMA_PID=$!

# Wait for Puma to start and be ready
echo -e "${YELLOW}Waiting for Puma to start...${NC}"
for i in {1..30}; do
    if curl -s http://localhost:$PORT > /dev/null 2>&1; then
        echo -e "${GREEN}Puma is ready!${NC}"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${RED}Puma failed to start within 30 seconds${NC}"
        exit 1
    fi
    sleep 1
done

# Run wrk benchmark
echo -e "${GREEN}Running wrk benchmark...${NC}"
echo "Command: $WRK_CMD"
$WRK_CMD

echo -e "${GREEN}Benchmark complete!${NC}"
