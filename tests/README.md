## pqcap tests

Current tests are SQL conformance checks focused on the Parquet metadata contract.

### DuckDB conformance

1. Ensure temp fixture directory exists:

```bash
mkdir -p .tmp/testdata
```

2. Run:

```bash
duckdb -unsigned < tests/duckdb/pqcap_metadata_contract.sql
```

The script verifies:

- required columns exist (`offset`, `size`, `ts_ns`, `linktype`)
- required types are query-compatible
- invariant checks (`size > 0`, basic overflow guard)
- a negative fixture is detectable (missing required column)

### DuckDB native-query integration

Verifies the no-sidecar prototype path:

```bash
bash tests/duckdb/integration_native_query.sh
```

### Packet-tool smoke (tshark)

This verifies packet-tool compatibility at a practical level by:

- generating a tiny capture fixture with `text2pcap`
- reading it with `tshark`
- asserting one packet is decoded

Run:

```bash
bash tests/pcap/smoke_tshark.sh
```

### SIP retention integration

Uses `tests/pcap/test001_sip_sippgen.pcap` and verifies key extracted fields are preserved in embedded metadata.

```bash
bash tests/pcap/integration_sip_retention.sh
```

### Run everything

```bash
bash tests/run_all.sh
```

### Build and smoke-test DuckDB extension

```bash
bash tests/extension/smoke_build_and_query.sh
```

### Validate a pqcap file directly

```bash
bash scripts/pqcap_validate.sh .tmp/examples/demo.pqcapng
```
