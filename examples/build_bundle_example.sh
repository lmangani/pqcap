#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_FILE="$ROOT_DIR/.tmp/examples/demo.pqcapng"
HEX_FILE="$ROOT_DIR/.tmp/examples/demo_capture.hex"
PCAP_FILE="$ROOT_DIR/.tmp/examples/demo_capture.pcapng"

mkdir -p "$ROOT_DIR/.tmp/examples"

cat > "$HEX_FILE" <<'EOF'
0000  ff ff ff ff ff ff 00 11 22 33 44 55 08 00 45 00
0010  00 1c 00 01 00 00 40 11 6a ce 7f 00 00 01 7f 00
0020  00 01 04 d2 16 2e 00 08 00 00
EOF

text2pcap "$HEX_FILE" "$PCAP_FILE" >/dev/null
bash "$ROOT_DIR/scripts/pqcap_from_pcap.sh" "$PCAP_FILE" "$OUT_FILE"

echo "PASS example file: $OUT_FILE"
