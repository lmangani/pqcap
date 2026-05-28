#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${ROOT_DIR}/.tmp/testdata"
HEX_FILE="${OUT_DIR}/tshark_smoke.hex"
PCAPNG_FILE="${OUT_DIR}/tshark_smoke.pcapng"

mkdir -p "${OUT_DIR}"

if ! command -v tshark >/dev/null 2>&1; then
  echo "FAIL: tshark not found in PATH"
  exit 1
fi

if ! command -v text2pcap >/dev/null 2>&1; then
  echo "FAIL: text2pcap not found in PATH"
  exit 1
fi

cat > "${HEX_FILE}" <<'EOF'
0000  ff ff ff ff ff ff 00 11 22 33 44 55 08 00 45 00
0010  00 1c 00 01 00 00 40 11 6a ce 7f 00 00 01 7f 00
0020  00 01 04 d2 16 2e 00 08 00 00
EOF

text2pcap "${HEX_FILE}" "${PCAPNG_FILE}" >/dev/null

PKT_COUNT="$(tshark -r "${PCAPNG_FILE}" -T fields -e frame.number | wc -l | tr -d ' ')"
if [[ "${PKT_COUNT}" != "1" ]]; then
  echo "FAIL: expected 1 packet, got ${PKT_COUNT}"
  exit 1
fi

PROTO_LINE="$(tshark -r "${PCAPNG_FILE}" -c 1 -T fields -e _ws.col.Protocol | head -n 1)"
if [[ -z "${PROTO_LINE}" ]]; then
  echo "FAIL: tshark produced empty protocol output"
  exit 1
fi

echo "PASS tshark smoke (${PROTO_LINE})"
