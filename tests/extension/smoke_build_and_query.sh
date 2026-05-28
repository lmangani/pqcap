#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXT_DIR="$ROOT_DIR/duckdb_pqcap_reader"
PQCAP_FILE="$ROOT_DIR/.tmp/examples/demo.pqcapng"

command -v make >/dev/null 2>&1 || { echo "FAIL: make required"; exit 1; }

if [[ ! -d "$EXT_DIR/duckdb" || ! -d "$EXT_DIR/extension-ci-tools" ]]; then
  echo "FAIL: extension submodules not initialized; run:"
  echo "  git -C duckdb_pqcap_reader submodule update --init --recursive"
  exit 1
fi

bash "$ROOT_DIR/examples/build_bundle_example.sh"

if command -v ninja >/dev/null 2>&1; then
  make -C "$EXT_DIR" GEN=ninja release >/dev/null
else
  make -C "$EXT_DIR" release >/dev/null
fi

DUCKDB_BIN="$EXT_DIR/build/release/duckdb"
[[ -x "$DUCKDB_BIN" ]] || { echo "FAIL: duckdb binary not built: $DUCKDB_BIN"; exit 1; }

META_RESULT="$("$DUCKDB_BIN" -unsigned -csv -c "SELECT COUNT(*) AS n FROM read_pqcap('$PQCAP_FILE');" | tail -n 1)"
[[ "$META_RESULT" =~ ^[0-9]+$ ]] || { echo "FAIL: invalid metadata query result '$META_RESULT'"; exit 1; }
[[ "$META_RESULT" -gt 0 ]] || { echo "FAIL: expected >0 rows from read_pqcap"; exit 1; }

PACKET_RESULT="$("$DUCKDB_BIN" -unsigned -csv -c "SELECT COUNT(*) AS n FROM read_pqcap_packets('$PQCAP_FILE') WHERE l4_protocol = 'UDP' AND src_port = 1234 AND dst_port = 5678;" | tail -n 1)"
[[ "$PACKET_RESULT" =~ ^[0-9]+$ ]] || { echo "FAIL: invalid packet query result '$PACKET_RESULT'"; exit 1; }
[[ "$PACKET_RESULT" -gt 0 ]] || { echo "FAIL: expected >0 rows from read_pqcap_packets conditional query"; exit 1; }

TYPE_RESULT="$("$DUCKDB_BIN" -unsigned -csv -c "SELECT typeof(timestamp_micros), typeof(src_ip), typeof(dst_ip), typeof(src_port), typeof(dst_port), typeof(l4_protocol), typeof(orig_len), typeof(payload) FROM read_pqcap_packets('$PQCAP_FILE') LIMIT 1;" | tail -n 1)"
[[ "$TYPE_RESULT" == "BIGINT,VARCHAR,VARCHAR,INTEGER,INTEGER,VARCHAR,UBIGINT,BLOB" ]] || {
  echo "FAIL: unexpected packet column types '$TYPE_RESULT'"
  exit 1
}

echo "PASS extension build/query smoke (meta=$META_RESULT, packets=$PACKET_RESULT)"
