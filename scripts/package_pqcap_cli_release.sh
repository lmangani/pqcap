#!/usr/bin/env bash
# Stage dist/pqcap as a platform-named release binary (uploaded as-is, not zipped).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASSET_NAME="${1:?usage: package_pqcap_cli_release.sh <name> e.g. pqcap-linux-amd64}"

BIN="${ROOT}/dist/pqcap"
OUT="${ROOT}/${ASSET_NAME}"

if [[ ! -f "${BIN}" ]]; then
  echo "FAIL: ${BIN} not found; run scripts/build_pqcap_cli.sh first" >&2
  exit 1
fi

cp "${BIN}" "${OUT}"
chmod +x "${OUT}"
echo "Prepared ${OUT}"
