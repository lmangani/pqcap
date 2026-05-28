#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$ROOT_DIR/.tmp/large_index"
HEX_FILE="$TMP_DIR/base.hex"
BASE_PCAP="$TMP_DIR/base.pcapng"
BIG_PARQUET="$TMP_DIR/metadata_large.parquet"
OUT_PQCAP="$TMP_DIR/large_index_test.pqcapng"

mkdir -p "$TMP_DIR"

command -v text2pcap >/dev/null 2>&1 || { echo "FAIL: text2pcap required"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 required"; exit 1; }
python3 -c "import duckdb" >/dev/null 2>&1 || { echo "FAIL: python duckdb package required"; exit 1; }

cat > "$HEX_FILE" <<'EOF'
0000  ff ff ff ff ff ff 00 11 22 33 44 55 08 00 45 00
0010  00 1c 00 01 00 00 40 11 6a ce 7f 00 00 01 7f 00
0020  00 01 04 d2 16 2e 00 08 00 00
EOF

text2pcap "$HEX_FILE" "$BASE_PCAP" >/dev/null

# 1,000-row metadata table to verify scalable-index behavior cheaply.
python3 - "$BIG_PARQUET" <<'PY'
import sys
import duckdb

big_parquet = sys.argv[1]
con = duckdb.connect()
con.execute(
    """
CREATE OR REPLACE TABLE t AS
SELECT
  CAST(i * 42 AS UBIGINT) AS "offset",
  CAST(42 AS UBIGINT) AS "size",
  CAST(1716800000000000000 + i AS UBIGINT) AS ts_ns,
  CAST(1 AS USMALLINT) AS linktype,
  CAST(i + 1 AS UBIGINT) AS frame_number,
  'eth:ip:udp' AS protocols,
  '10.0.0.1' AS src_ip,
  CAST(5060 AS UINTEGER) AS src_port,
  '10.0.0.2' AS dst_ip,
  CAST(5060 AS UINTEGER) AS dst_port
FROM range(1000) r(i)
"""
)
con.execute(f"COPY t TO '{big_parquet}' (FORMAT PARQUET)")
PY

python3 "$ROOT_DIR/scripts/pqcap_embedded_metadata.py" append "$BASE_PCAP" "$BIG_PARQUET" "$OUT_PQCAP"

RESULT="$(python3 "$ROOT_DIR/scripts/pqcap_duckdb_query.py" "$OUT_PQCAP" \
  --sql "SELECT COUNT(*) AS n FROM pqcap_meta" | tail -n 1)"
[[ "$RESULT" == "1000" ]] || { echo "FAIL: expected 1000 rows, got '$RESULT'"; exit 1; }

echo "PASS large-index smoke (1,000 rows)"
