#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> DuckDB metadata contract"
mkdir -p .tmp/testdata
duckdb -unsigned < tests/duckdb/pqcap_metadata_contract.sql

echo "==> DuckDB native-query integration"
bash tests/duckdb/integration_native_query.sh

echo "==> DuckDB extension integration"
bash tests/extension/smoke_build_and_query.sh

echo "==> Large-index smoke"
bash tests/duckdb/large_index_smoke.sh

echo "==> tshark smoke"
bash tests/pcap/smoke_tshark.sh

echo "==> SIP retention integration"
bash tests/pcap/integration_sip_retention.sh

echo "==> pqcap single-file build + query smoke"
bash examples/build_bundle_example.sh
bash scripts/pqcap_validate.sh .tmp/examples/demo.pqcapng
bash scripts/pqcap_query.sh .tmp/examples/demo.pqcapng "protocols LIKE '%udp%' OR protocols LIKE '%sip%'"

echo "PASS all tests"
