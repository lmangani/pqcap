<img width="300" alt="pqcap" src="https://github.com/user-attachments/assets/bcc8c286-1d67-4c5e-baa9-6e7342709879" />

# pqcap

PCAP-NG-compatible capture packaging with a Parquet query plane.

`pqcap` is built for teams that need both packet-tool fidelity and SQL/dataframe query speed.

## What you get

- **Packet compatibility**: capture payload remains usable with packet tools like `tshark`.
- **Query compatibility**: metadata is standard Parquet, directly readable by DuckDB and other Parquet readers.
- **Practical validation**: one-command checks for packet decode + metadata contract.
- **Range-readability**: embedded metadata is discoverable from a fixed footer, so readers can fetch only footer + metadata bytes first.

Current release candidate: `0.1.0-rc1`.

## Made for Integrators

Typical network and observability workloads need:

- byte-accurate packet evidence for protocol/debug workflows
- high-speed filtering and analytics on metadata fields (time, IPs, ports, SIP keys)

`pqcap` bridges these in a single-file flow.

## Single-file model (current draft)

Each artifact is one file (`.pqcapng`):

- packet plane: PCAP-NG records
- query plane: embedded Parquet metadata block

## Install prerequisites

- `tshark` and `text2pcap`
- `duckdb`

## End-to-end example

### 1) Build a demo file

```bash
bash examples/build_bundle_example.sh
```

This creates `.tmp/examples/demo.pqcapng`.

### 2) Query with DuckDB

```bash
bash scripts/pqcap_query.sh .tmp/examples/demo.pqcapng "protocols LIKE '%udp%'"
```

Native in-memory Python path (no metadata extraction to disk):

```bash
python3 scripts/pqcap_duckdb_query.py .tmp/examples/demo.pqcapng --sql "SELECT frame_number, protocols, \"size\" FROM pqcap_meta LIMIT 10"
```

DuckDB extension SQL path (`read_pqcap`):

```bash
make -C duckdb_pqcap_reader release
./duckdb_pqcap_reader/build/release/duckdb -unsigned -c "SELECT COUNT(*) FROM read_pqcap('.tmp/examples/demo.pqcapng');"
```

Remote/object URL path (range reads: footer then metadata):

```bash
python3 scripts/pqcap_duckdb_query.py "https://example.org/capture/demo.pqcapng" --sql "SELECT COUNT(*) AS n FROM pqcap_meta"
```

Equivalent direct SQL (extract embedded metadata first):

```bash
python3 scripts/pqcap_embedded_metadata.py extract .tmp/examples/demo.pqcapng .tmp/examples/demo.parquet
duckdb -c "SELECT frame_number, ts_ns, src_ip, src_port, dst_ip, dst_port, \"offset\", \"size\" FROM read_parquet('.tmp/examples/demo.parquet') WHERE protocols LIKE '%udp%' ORDER BY frame_number;"
```

### 3) Inspect packets with tshark

```bash
tshark -r .tmp/examples/demo.pqcapng -c 10
```

### 4) Validate the file

```bash
bash scripts/pqcap_validate.sh .tmp/examples/demo.pqcapng
```

## SIP sample integration example

Use the included SIP sample capture and build a `.pqcapng` file:

```bash
bash scripts/pqcap_from_pcap.sh tests/pcap/test001_sip_sippgen.pcap .tmp/examples/sip_test.pqcapng
```

Query SIP-focused fields:

```bash
python3 scripts/pqcap_embedded_metadata.py extract .tmp/examples/sip_test.pqcapng .tmp/examples/sip_test.parquet
duckdb -c "SELECT frame_number, sip_call_id, sip_method, sip_status_code, sip_cseq_method FROM read_parquet('.tmp/examples/sip_test.parquet') WHERE sip_call_id IS NOT NULL ORDER BY frame_number LIMIT 20;"
```

The integration test `tests/pcap/integration_sip_retention.sh` verifies key extracted fields are retained from source capture to metadata.

## Testing and release checks

Run full suite:

```bash
bash tests/run_all.sh
```

`tests/run_all.sh` now cross-tests:

- Python native query path
- DuckDB extension path (`read_pqcap`)
- packet-tool compatibility
- SIP retention
- scale smoke checks

Release gate:

```bash
make release-check
```

Extension smoke test:

```bash
make extension-smoke
```

## DuckDB extension status

`duckdb_pqcap_reader` is now included as a submodule and wired into project smoke tests.

Current recommended development/testing modes:

- Python native query path (`scripts/pqcap_duckdb_query.py`) for fast iteration
- DuckDB extension path (`read_pqcap`) for SQL-native integration validation

## Project docs

- Format contract: `SPEC.md`
- Integration details: `docs/INTEGRATION_GUIDE.md`
- Release process: `docs/RELEASE.md`
- Architecture notes: `docs/PQCAP_ARCHITECTURE.md`
