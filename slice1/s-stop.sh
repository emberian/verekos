#!/usr/bin/env bash
# slice1/s-stop.sh — stop this run's service by the PID the bootstrap wrote (world/public/server.pid),
# after checking that PID is a `mini serve` on this run's socket. Never by pattern.
. "$(dirname "$0")/world-lib.sh"
pid=$(cat "$W/public/server.pid" 2>/dev/null) || { echo "no server.pid"; exit 0; }
kill -0 "$pid" 2>/dev/null || { echo "server $pid already gone"; exit 0; }
case "$(ps -o args= -p "$pid")" in *" serve "*"--socket $SOCKET"*) ;; *) echo "pid $pid is not this run's server; not signalling" >&2; exit 1;; esac
kill -TERM "$pid"
for i in $(seq 1 300); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
kill -0 "$pid" 2>/dev/null && { echo "server $pid alive 30 s after TERM" >&2; exit 1; }
echo "stopped server $pid"
