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

echo "PASS pqcap cli smoke (meta=${META_COUNT}, packets=${PACKET_COUNT})"
