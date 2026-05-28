#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <input.pqcapng>"
  exit 1
fi

PQCAP_FILE="$1"
TMP_PARQUET="$(mktemp)"
trap 'rm -f "$TMP_PARQUET"' EXIT

fail() {
  echo "FAIL: $1"
  exit 1
}

[[ -f "$PQCAP_FILE" ]] || fail "pqcap file not found: $PQCAP_FILE"

command -v tshark >/dev/null 2>&1 || fail "tshark is required"
command -v duckdb >/dev/null 2>&1 || fail "duckdb is required"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"

python3 scripts/pqcap_embedded_metadata.py extract "$PQCAP_FILE" "$TMP_PARQUET" || fail "embedded metadata block not found"

# Packet decode smoke.
PKT_COUNT="$(tshark -r "$PQCAP_FILE" -T fields -e frame.number | wc -l | tr -d ' ')"
[[ "$PKT_COUNT" =~ ^[0-9]+$ ]] || fail "invalid packet count from tshark"
(( PKT_COUNT > 0 )) || fail "capture has no decodable packets"

# Metadata contract checks.
duckdb <<SQL
CREATE OR REPLACE TEMP VIEW v_meta AS
SELECT * FROM read_parquet('$TMP_PARQUET');

SELECT CASE
  WHEN COUNT(*) = 4 THEN 1
  ELSE error('missing required columns')
END
FROM information_schema.columns
WHERE table_name = 'v_meta'
  AND column_name IN ('offset', 'size', 'ts_ns', 'linktype');

SELECT CASE
  WHEN COUNT(*) = 0 THEN 1
  ELSE error('size must be > 0')
END
FROM v_meta
WHERE "size" <= 0;

SELECT CASE
  WHEN COUNT(*) = 0 THEN 1
  ELSE error('offset+size overflow detected')
END
FROM v_meta
WHERE ("offset" + "size") < "offset";

SELECT CASE
  WHEN COUNT(*) > 0 THEN 1
  ELSE error('metadata is empty')
END
FROM v_meta;
SQL

echo "PASS pqcap file validation: $PQCAP_FILE"
