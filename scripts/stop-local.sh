#!/usr/bin/env bash
#
# stop-local.sh — tear down the local baseline started by start-local.sh.
#
#   1. Stops the Angular dev server.
#   2. Stops the Spring Boot backend (and any child processes).
#   3. Stops the MySQL container.
#
# Usage:
#   ./scripts/stop-local.sh
#   ./scripts/stop-local.sh --keep-db   # leave the MySQL container running

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/scripts/logs"

KEEP_DB=0
[ "${1:-}" = "--keep-db" ] && KEEP_DB=1

# kill_tree <pid> — kill a process and its descendants (best effort).
kill_tree() {
  local pid="$1"
  [ -z "$pid" ] && return 0
  # Kill children first (handles Maven -> forked Java, npm -> ng).
  pkill -TERM -P "$pid" 2>/dev/null || true
  kill -TERM "$pid" 2>/dev/null || true
  sleep 2
  pkill -KILL -P "$pid" 2>/dev/null || true
  kill -KILL "$pid" 2>/dev/null || true
}

stop_from_pidfile() {
  local name="$1"; local file="$LOG_DIR/$1.pid"
  if [ -f "$file" ]; then
    local pid; pid="$(cat "$file" 2>/dev/null)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "==> Stopping $name (pid $pid)..."
      kill_tree "$pid"
    else
      echo "==> $name not running (stale pid file)."
    fi
    rm -f "$file"
  else
    echo "==> No $name.pid file — nothing to stop."
  fi
}

stop_from_pidfile frontend
stop_from_pidfile backend

# Safety net: kill any lingering ng serve / spring-boot:run for this project.
pkill -f "ng serve" 2>/dev/null || true
pkill -f "spring-boot:run" 2>/dev/null || true

if [ "$KEEP_DB" -eq 0 ]; then
  echo "==> Stopping MySQL container..."
  ( cd "$ROOT_DIR/docker-test-db" && docker compose down )
else
  echo "==> Leaving MySQL container running (--keep-db)."
fi

echo "==> Local baseline stopped."
