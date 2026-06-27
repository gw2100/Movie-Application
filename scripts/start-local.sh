#!/usr/bin/env bash
#
# start-local.sh — bring up the full local baseline (DB + backend + frontend).
#
#   1. Starts the MySQL (Sakila) container and waits until it is ready.
#   2. Starts the Spring Boot backend on JDK 8 (background).
#   3. Starts the Angular dev server on Node 12 (background).
#
# Logs:  scripts/logs/{backend,frontend}.log
# PIDs:  scripts/logs/{backend,frontend}.pid
#
# Usage:
#   ./scripts/start-local.sh
#
# Optional environment overrides:
#   JAVA_8_HOME   path to a JDK 8 install (else auto-detected)
#   NODE_VERSION  nvm node version to use (default 12)
#
# Stop everything again with ./scripts/stop-local.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/scripts/logs"
mkdir -p "$LOG_DIR"

NODE_VERSION="${NODE_VERSION:-12}"

# ---- 1. Database -----------------------------------------------------------
echo "==> Starting MySQL (Sakila) container..."
( cd "$ROOT_DIR/docker-test-db" && docker compose up -d )

echo -n "==> Waiting for MySQL to accept connections and load Sakila"
for _ in $(seq 1 60); do
  if docker exec movie-db mysql -uroot -proot -e "SELECT COUNT(*) FROM sakila.film" >/dev/null 2>&1; then
    echo " — ready."
    break
  fi
  echo -n "."
  sleep 3
done

# ---- 2. Backend ------------------------------------------------------------
if [ -n "${JAVA_8_HOME:-}" ]; then
  JAVA_HOME="$JAVA_8_HOME"
elif /usr/libexec/java_home -v 1.8 >/dev/null 2>&1; then
  JAVA_HOME="$(/usr/libexec/java_home -v 1.8)"
elif [ -d "/Library/Java/JavaVirtualMachines/jdk1.8.0_231.jdk/Contents/Home" ]; then
  JAVA_HOME="/Library/Java/JavaVirtualMachines/jdk1.8.0_231.jdk/Contents/Home"
else
  echo "ERROR: Could not locate a JDK 8. Set JAVA_8_HOME to your JDK 8 install." >&2
  exit 1
fi
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"
export SPRING_DATASOURCE_URL="jdbc:mysql://localhost:3306/sakila?allowPublicKeyRetrieval=true&useSSL=false"
export SPRING_DATASOURCE_USERNAME=root
export SPRING_DATASOURCE_PASSWORD=root

echo "==> Starting Spring Boot backend (JDK 8) -> $LOG_DIR/backend.log"
( cd "$ROOT_DIR" && nohup mvn -pl movie-backend spring-boot:run > "$LOG_DIR/backend.log" 2>&1 & echo $! > "$LOG_DIR/backend.pid" )

echo -n "==> Waiting for backend on http://localhost:8080"
for _ in $(seq 1 60); do
  if curl -fsS -o /dev/null "http://localhost:8080/api/film/getAllFilm" 2>/dev/null; then
    echo " — up."
    break
  fi
  echo -n "."
  sleep 3
done

# ---- 3. Frontend -----------------------------------------------------------
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
# shellcheck disable=SC1091
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

echo "==> Starting Angular dev server (Node $NODE_VERSION) -> $LOG_DIR/frontend.log"
(
  cd "$ROOT_DIR/movie-frontend"
  if command -v nvm >/dev/null 2>&1; then nvm use "$NODE_VERSION" >/dev/null; fi
  nohup npm start > "$LOG_DIR/frontend.log" 2>&1 &
  echo $! > "$LOG_DIR/frontend.pid"
)

echo
echo "=============================================="
echo " Baseline starting up:"
echo "   MySQL     : localhost:3306 (container 'movie-db')"
echo "   Backend   : http://localhost:8080  (log: scripts/logs/backend.log)"
echo "   Frontend  : http://localhost:4200  (log: scripts/logs/frontend.log)"
echo
echo " The Angular dev server takes ~1-2 min to compile on first start."
echo " Tail it with:  tail -f scripts/logs/frontend.log"
echo " Verify with :  ./scripts/smoke-test.sh"
echo " Stop with   :  ./scripts/stop-local.sh"
echo "=============================================="
