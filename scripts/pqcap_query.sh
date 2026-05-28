#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <input.pqcapng> [where_sql]"
  exit 1
fi

PQCAP_FILE="$1"
WHERE_SQL="${2:-size > 0}"
if [[ ! -f "$PQCAP_FILE" ]]; then
  echo "FAIL: pqcap file not found at $PQCAP_FILE"
  exit 1
fi

TMP_PARQUET="$(mktemp)"
trap 'rm -f "$TMP_PARQUET"' EXIT

python3 scripts/pqcap_embedded_metadata.py extract "$PQCAP_FILE" "$TMP_PARQUET"

duckdb <<SQL
SELECT
  frame_number,
  ts_ns,
  protocols,
  src_ip,
  src_port,
  dst_ip,
  dst_port,
  "offset",
  "size"
FROM read_parquet('$TMP_PARQUET')
WHERE $WHERE_SQL
ORDER BY frame_number
LIMIT 50;
SQL
