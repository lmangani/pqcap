#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PQCAP="${ROOT}/dist/pqcap"
# Committed capture for CI/release (no text2pcap/tshark/python duckdb required).
FIXTURE="${PQCAP_SMOKE_FIXTURE:-${ROOT}/tests/fixtures/demo.pqcapng}"

if [[ ! -x "${PQCAP}" ]]; then
  echo "FAIL: ${PQCAP} not found; run scripts/build_pqcap_cli.sh"
  exit 1
fi

if [[ ! -f "${FIXTURE}" ]]; then
  echo "FAIL: smoke fixture missing: ${FIXTURE}"
  exit 1
fi

"${PQCAP}" version >/dev/null

META_COUNT="$("${PQCAP}" query -c "SELECT COUNT(*)::BIGINT AS n FROM read_pqcap('${FIXTURE}');" | grep -E '^[0-9]+$' | tail -n 1)"
[[ "${META_COUNT}" -gt 0 ]] || {
  echo "FAIL: expected metadata rows from read_pqcap"
  exit 1
}

PACKET_COUNT="$("${PQCAP}" query -c "SELECT COUNT(*)::BIGINT AS n FROM read_pqcap_packets('${FIXTURE}') WHERE l4_protocol = 'UDP';" | grep -E '^[0-9]+$' | tail -n 1)"
[[ "${PACKET_COUNT}" -gt 0 ]] || {
  echo "FAIL: expected packet rows from read_pqcap_packets"
  exit 1
}

CONVERT_DIR="${ROOT}/.tmp/cli_smoke"
PLAIN="${CONVERT_DIR}/plain.pcapng"
CONVERTED="${CONVERT_DIR}/indexed.pqcapng"
mkdir -p "${CONVERT_DIR}"

"${PQCAP}" query -c "COPY (SELECT timestamp_micros, orig_len, payload, src_ip, src_port, dst_ip, dst_port, l4_protocol FROM read_pqcap_packets('${FIXTURE}')) TO '${PLAIN}' (FORMAT pcapng, mode 'pcapng');" >/dev/null

"${PQCAP}" convert "${PLAIN}" "${CONVERTED}" >/dev/null

CONVERT_META="$("${PQCAP}" query -c "SELECT COUNT(*)::BIGINT AS n FROM read_pqcap('${CONVERTED}');" | grep -E '^[0-9]+$' | tail -n 1)"
[[ "${CONVERT_META}" -gt 0 ]] || {
  echo "FAIL: convert did not produce queryable pqcap metadata"
  exit 1
}

echo "PASS pqcap cli smoke (meta=${META_COUNT}, packets=${PACKET_COUNT}, convert=${CONVERT_META})"
