#!/bin/bash
# Throwaway spike: freeze a running app for N seconds, then resume it.
# Usage: freeze.sh "Messages" [seconds]
set -euo pipefail
NAME="$1"; SECS="${2:-6}"
PID="$(pgrep -x "$NAME" | head -1)"
[ -n "$PID" ] || { echo "$NAME is not running"; exit 1; }
echo "SIGSTOP $NAME (pid $PID) for ${SECS}s — try to interact with it, watch for a beachball"
kill -STOP "$PID"
sleep "$SECS"
kill -CONT "$PID"
echo "SIGCONT sent — check the app resumed with its state intact"
