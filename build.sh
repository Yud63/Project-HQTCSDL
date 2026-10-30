#!/usr/bin/env bash
# Usage: ./build.sh [server] [rebuild 0|1] [user] [password]
# Mac dinh dung SQL auth (sa) vi Linux/macOS khong co Windows auth.
set -euo pipefail
SERVER="${1:-localhost}"; REBUILD="${2:-1}"; USER_="${3:-sa}"; PASS="${4:-${SA_PASSWORD:-}}"
cd "$(dirname "$0")/database"
sqlcmd -S "$SERVER" -U "$USER_" -P "$PASS" -C -b -f 65001 -v ROOT="." REBUILD="$REBUILD" -i 99_run_all.sql
cd ../tests
sqlcmd -S "$SERVER" -U "$USER_" -P "$PASS" -C -b -f 65001 -i 00_smoke_test.sql
sqlcmd -S "$SERVER" -U "$USER_" -P "$PASS" -C -b -f 65001 -i 01_schema_check.sql
