#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INPUT_PCAP="$ROOT_DIR/tests/pcap/test001_sip_sippgen.pcap"
OUT_FILE="$ROOT_DIR/.tmp/examples/sip_test.pqcapng"
SRC_CSV="$ROOT_DIR/.tmp/testdata/sip_source.csv"
META_TMP="$ROOT_DIR/.tmp/testdata/sip_embedded.parquet"

[[ -f "$INPUT_PCAP" ]] || { echo "FAIL: missing sample pcap: $INPUT_PCAP"; exit 1; }
command -v tshark >/dev/null 2>&1 || { echo "FAIL: tshark required"; exit 1; }
command -v duckdb >/dev/null 2>&1 || { echo "FAIL: duckdb required"; exit 1; }

mkdir -p "$ROOT_DIR/.tmp/testdata"

bash "$ROOT_DIR/scripts/pqcap_from_pcap.sh" "$INPUT_PCAP" "$OUT_FILE"
bash "$ROOT_DIR/scripts/pqcap_validate.sh" "$OUT_FILE"
python3 "$ROOT_DIR/scripts/pqcap_embedded_metadata.py" extract "$OUT_FILE" "$META_TMP"

tshark -r "$INPUT_PCAP" \
  -T fields \
  -E header=y \
  -E separator=, \
  -E quote=d \
  -e frame.number \
  -e frame.time_epoch \
  -e frame.cap_len \
  -e frame.protocols \
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
  > "$SRC_CSV"

duckdb <<SQL
CREATE OR REPLACE TABLE src AS
SELECT
  CAST("frame.number" AS UBIGINT) AS frame_number,
  CAST(ROUND(CAST("frame.time_epoch" AS DOUBLE) * 1000000000) AS UBIGINT) AS ts_ns,
  CAST("frame.cap_len" AS UBIGINT) AS size,
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
FROM read_csv_auto('$SRC_CSV', HEADER=TRUE)
WHERE CAST("frame.cap_len" AS UBIGINT) > 0;

CREATE OR REPLACE TABLE meta AS
SELECT
  frame_number,
  ts_ns,
  size,
  protocols,
  src_ip,
  dst_ip,
  src_port,
  dst_port,
  sip_call_id,
  sip_method,
  sip_status_code,
  sip_cseq_method
FROM read_parquet('$META_TMP');

SELECT CASE
  WHEN (SELECT COUNT(*) FROM src) = (SELECT COUNT(*) FROM meta) THEN 1
  ELSE error('row count mismatch between source capture and metadata')
END;

SELECT CASE
  WHEN (
    SELECT COUNT(*) FROM (
      SELECT * FROM src
      EXCEPT
      SELECT * FROM meta
    )
  ) = 0 THEN 1
  ELSE error('metadata mismatch: src minus meta is not empty')
END;

SELECT CASE
  WHEN (
    SELECT COUNT(*) FROM (
      SELECT * FROM meta
      EXCEPT
      SELECT * FROM src
    )
  ) = 0 THEN 1
  ELSE error('metadata mismatch: meta minus src is not empty')
END;
SQL

echo "PASS SIP retention integration test"
