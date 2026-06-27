#!/usr/bin/env bash
#
# smoke-test.sh — end-to-end baseline smoke test for Movie-Application.
#
# Verifies the three running tiers:
#   1. MySQL (Sakila) container + seed data
#   2. Spring Boot REST API (/api/film/*)
#   3. Angular frontend (dev server)
#
# Usage:
#   ./scripts/smoke-test.sh
#
# Optional environment overrides:
#   BACKEND_URL   (default http://localhost:8080)
#   FRONTEND_URL  (default http://localhost:4200)
#   DB_CONTAINER  (default movie-db)
#
# Exit code is non-zero if any check fails.

set -uo pipefail

BACKEND_URL="${BACKEND_URL:-http://localhost:8080}"
FRONTEND_URL="${FRONTEND_URL:-http://localhost:4200}"
DB_CONTAINER="${DB_CONTAINER:-movie-db}"

PASS=0
FAIL=0

green() { printf '\033[32m%s\033[0m' "$1"; }
red()   { printf '\033[31m%s\033[0m' "$1"; }

# check <description> <command...>
# Passes if the command exits 0.
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "  [$(green PASS)] $desc"
    PASS=$((PASS + 1))
  else
    echo "  [$(red FAIL)] $desc"
    FAIL=$((FAIL + 1))
  fi
}

# check_contains <description> <expected substring> <command...>
# Passes if the command's stdout contains the expected substring.
check_contains() {
  local desc="$1"; local expected="$2"; shift 2
  local out
  out="$("$@" 2>/dev/null)"
  if [[ "$out" == *"$expected"* ]]; then
    echo "  [$(green PASS)] $desc"
    PASS=$((PASS + 1))
  else
    echo "  [$(red FAIL)] $desc (expected to contain: '$expected')"
    FAIL=$((FAIL + 1))
  fi
}

echo "=============================================="
echo " Movie-Application baseline smoke test"
echo "=============================================="

echo
echo "1) Database (MySQL / Sakila)"
if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$DB_CONTAINER"; then
  check "container '$DB_CONTAINER' is running" true
  FILM_COUNT="$(docker exec "$DB_CONTAINER" mysql -uroot -proot -N -e "SELECT COUNT(*) FROM sakila.film" 2>/dev/null | tr -d '[:space:]')"
  if [[ "$FILM_COUNT" =~ ^[0-9]+$ ]] && [ "$FILM_COUNT" -ge 1000 ]; then
    echo "  [$(green PASS)] sakila.film is seeded ($FILM_COUNT rows)"
    PASS=$((PASS + 1))
  else
    echo "  [$(red FAIL)] sakila.film seed check (got: '${FILM_COUNT:-<none>}', expected >= 1000)"
    FAIL=$((FAIL + 1))
  fi
else
  echo "  [skip] docker/container '$DB_CONTAINER' not available — skipping direct DB checks"
fi

echo
echo "2) Backend REST API ($BACKEND_URL)"
check_contains "GET /api/film/getAllFilm returns ACADEMY DINOSAUR" "ACADEMY DINOSAUR" \
  curl -fsS "$BACKEND_URL/api/film/getAllFilm"
check_contains "GET /api/film/search/ACADEMY returns a match" "ACADEMY" \
  curl -fsS "$BACKEND_URL/api/film/search/ACADEMY"
check_contains "GET /api/film/movieDetails/1 returns film 1" "\"filmId\":1" \
  curl -fsS "$BACKEND_URL/api/film/movieDetails/1"
check_contains "GET /api/film/category/6 returns films" "filmId" \
  curl -fsS "$BACKEND_URL/api/film/category/6"
check_contains "GET /api/film/getAllFilmByActor/1 returns films" "filmId" \
  curl -fsS "$BACKEND_URL/api/film/getAllFilmByActor/1"

echo
echo "3) Frontend (Angular dev server, $FRONTEND_URL)"
check "frontend responds on $FRONTEND_URL" curl -fsS -o /dev/null "$FRONTEND_URL"
check_contains "frontend serves the Angular app shell" "<app-root>" \
  curl -fsS "$FRONTEND_URL"

echo
echo "=============================================="
echo " Results: $(green "$PASS passed"), $([ "$FAIL" -gt 0 ] && red "$FAIL failed" || echo "0 failed")"
echo "=============================================="

[ "$FAIL" -eq 0 ]
