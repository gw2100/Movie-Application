#!/usr/bin/env bash
#
# backend-test.sh — run the Spring Boot backend unit tests on JDK 8.
#
# Spring Boot 2.4.5 does not run on modern JDKs, so this pins JAVA_HOME to a
# JDK 8 install before invoking Maven.
#
# Usage:
#   ./scripts/backend-test.sh
#
# Optional environment override:
#   JAVA_8_HOME  (default: macOS JDK 8 location via /usr/libexec/java_home -v 1.8)

set -euo pipefail

# Resolve a JDK 8 home: explicit override > macOS java_home > common path.
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

echo "Using JDK:"
java -version

# Run from the repo root regardless of where the script is invoked.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo
echo "Running backend tests (mvn -pl movie-backend -am test)..."
mvn -pl movie-backend -am test
