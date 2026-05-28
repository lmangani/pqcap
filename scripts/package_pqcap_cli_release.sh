#!/usr/bin/env bash
# Package dist/pqcap as a release zip (pqcap executable at archive root).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASSET_BASENAME="${1:?usage: package_pqcap_cli_release.sh <basename> e.g. pqcap-linux-amd64}"

BIN="${ROOT}/dist/pqcap"
OUT="${ROOT}/${ASSET_BASENAME}.zip"

if [[ ! -f "${BIN}" ]]; then
  echo "FAIL: ${BIN} not found; run scripts/build_pqcap_cli.sh first" >&2
  exit 1
fi

chmod +x "${BIN}"
rm -f "${OUT}"
(cd "${ROOT}/dist" && zip -j "${OUT}" pqcap)

echo "Packaged ${OUT}"
