#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_FILE="$ROOT_DIR/.tmp/examples/native_query_test.pqcapng"

command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 required"; exit 1; }

bash "$ROOT_DIR/examples/build_bundle_example.sh"
cp "$ROOT_DIR/.tmp/examples/demo.pqcapng" "$OUT_FILE"

RESULT="$(python3 "$ROOT_DIR/scripts/pqcap_duckdb_query.py" "$OUT_FILE" \
  --sql "SELECT COUNT(*) AS n FROM pqcap_meta WHERE \"size\" > 0" | tail -n 1)"
[[ "$RESULT" == "1" ]] || { echo "FAIL: expected row count 1, got '$RESULT'"; exit 1; }

echo "PASS native in-memory DuckDB query"
