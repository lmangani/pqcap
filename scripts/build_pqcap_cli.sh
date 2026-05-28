#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXT_DIR="${ROOT}/duckdb_pqcap_reader"
BUILD_DIR="${ROOT}/build/cli"
DIST_DIR="${ROOT}/dist"

echo "Building DuckDB extension (static)..."
make -C "${EXT_DIR}" release

cmake -S "${ROOT}/cli" -B "${BUILD_DIR}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DDUCKDB_BUILD_DIR="${EXT_DIR}/build/release" \
  -DDUCKDB_SOURCE_DIR="${EXT_DIR}/duckdb" \
  -DPQCAP_EXTENSION_DIR="${EXT_DIR}"

cmake --build "${BUILD_DIR}" --config Release -j

mkdir -p "${DIST_DIR}"
cp "${BUILD_DIR}/pqcap" "${DIST_DIR}/pqcap"
if command -v strip >/dev/null 2>&1; then
  strip "${DIST_DIR}/pqcap" || true
fi

echo "Built ${DIST_DIR}/pqcap"
