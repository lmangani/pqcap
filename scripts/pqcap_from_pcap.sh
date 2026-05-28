#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <input.pcap|input.pcapng> <output.pqcapng>"
  exit 1
fi

INPUT_PCAP="$1"
OUTPUT_PQCAP="$2"

if [[ ! -f "$INPUT_PCAP" ]]; then
  echo "FAIL: input capture not found: $INPUT_PCAP"
  exit 1
fi

if ! command -v tshark >/dev/null 2>&1; then
  echo "FAIL: tshark is required"
  exit 1
fi

if ! command -v duckdb >/dev/null 2>&1; then
  echo "FAIL: duckdb is required"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL: python3 is required"
  exit 1
fi

OUT_DIR="$(dirname "$OUTPUT_PQCAP")"
mkdir -p "$OUT_DIR"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

RAW_CSV="$TMP_DIR/packets_raw.csv"
METADATA_PARQUET="$TMP_DIR/metadata.parquet"
CAPTURE_PCAPNG="$TMP_DIR/capture.pcapng"

# Ensure output capture bytes are PCAP-NG regardless of input flavor.
tshark -r "$INPUT_PCAP" -F pcapng -w "$CAPTURE_PCAPNG" >/dev/null 2>&1

tshark -r "$INPUT_PCAP" \
  -T fields \
  -E header=y \
  -E separator=, \
  -E quote=d \
  -e frame.number \
  -e frame.time_epoch \
  -e frame.cap_len \
  -e frame.len \
  -e frame.protocols \
  -e frame.encap_type \
  -e ip.src \
  -e ip.dst \
  -e tcp.srcport \
  -e tcp.dstport \
  -e udp.srcport \
  -e udp.dstport \
  -e sip.Call-ID \
  -e sip.Method \
  -e sip.Status-Code \
  -e sip.CSeq.method \
  > "$RAW_CSV"

duckdb <<SQL
CREATE OR REPLACE TABLE raw AS
SELECT * FROM read_csv_auto('$RAW_CSV', HEADER=TRUE);

CREATE OR REPLACE TABLE pqcap_metadata AS
SELECT
  CAST(
    COALESCE(
      SUM(CAST("frame.cap_len" AS UBIGINT))
      OVER (
        ORDER BY CAST("frame.number" AS UBIGINT)
        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
      ),
      0
    ) AS UBIGINT
  ) AS offset,
  CAST("frame.cap_len" AS UBIGINT) AS size,
  CAST(ROUND(CAST("frame.time_epoch" AS DOUBLE) * 1000000000) AS UBIGINT) AS ts_ns,
  CAST(COALESCE(CAST("frame.encap_type" AS UINTEGER), 0) AS USMALLINT) AS linktype,
  CAST("frame.number" AS UBIGINT) AS frame_number,
  "frame.protocols" AS protocols,
  NULLIF("ip.src", '') AS src_ip,
  NULLIF("ip.dst", '') AS dst_ip,
  CAST(
    NULLIF(
      COALESCE(
        CAST("tcp.srcport" AS VARCHAR),
        CAST("udp.srcport" AS VARCHAR)
      ),
      ''
    ) AS UINTEGER
  ) AS src_port,
  CAST(
    NULLIF(
      COALESCE(
        CAST("tcp.dstport" AS VARCHAR),
        CAST("udp.dstport" AS VARCHAR)
      ),
      ''
    ) AS UINTEGER
  ) AS dst_port,
  NULLIF("sip.Call-ID", '') AS sip_call_id,
  NULLIF("sip.Method", '') AS sip_method,
  CAST(NULLIF("sip.Status-Code", '') AS UINTEGER) AS sip_status_code,
  NULLIF("sip.CSeq.method", '') AS sip_cseq_method
FROM raw
WHERE CAST("frame.cap_len" AS UBIGINT) > 0
ORDER BY CAST("frame.number" AS UBIGINT);

COPY pqcap_metadata TO '$METADATA_PARQUET' (FORMAT PARQUET);
SQL

python3 scripts/pqcap_embedded_metadata.py append "$CAPTURE_PCAPNG" "$METADATA_PARQUET" "$OUTPUT_PQCAP"

echo "PASS pqcap single-file created: $OUTPUT_PQCAP"
