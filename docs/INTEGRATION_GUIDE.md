## Integration guide

This guide is for integrators who need two things at once:

1. packet-tool compatibility (`tshark`, protocol workflows)
2. query compatibility (`DuckDB` and Parquet tooling)

## Draft artifact layout

Current practical output from `scripts/pqcap_from_pcap.sh` is one `.pqcapng` file:

- packet plane: regular PCAP-NG records
- query plane: embedded Parquet metadata block
- range locator: fixed-size final custom block for metadata offset/length discovery

## Build from a capture

```bash
bash scripts/pqcap_from_pcap.sh input.pcapng output.pqcapng
```

## Query from DuckDB

```bash
bash scripts/pqcap_query.sh output.pqcapng "protocols LIKE '%udp%'"
```

No-sidecar prototype (in-memory):

```bash
python3 scripts/pqcap_duckdb_query.py output.pqcapng --sql "SELECT frame_number, protocols, \"size\" FROM pqcap_meta LIMIT 20"
```

Remote/object read using byte ranges:

```bash
python3 scripts/pqcap_duckdb_query.py "https://example.org/path/capture.pqcapng" --sql "SELECT COUNT(*) AS n FROM pqcap_meta"
```

Or directly:

```sql
SELECT frame_number, src_ip, src_port, dst_ip, dst_port, offset, size
FROM read_parquet('extracted_metadata.parquet')
WHERE size > 0
ORDER BY frame_number;
```

To get `extracted_metadata.parquet`:

```bash
python3 scripts/pqcap_embedded_metadata.py extract output.pqcapng extracted_metadata.parquet
```

The long-term target is a native DuckDB extension table function so this path is available directly in SQL without Python glue, while preserving the same range-read behavior.

## Packet-tool verification

```bash
tshark -r output.pqcapng -c 10
```

## Conformance checks

Run all tests:

```bash
bash tests/run_all.sh
```

This runs:

- DuckDB metadata contract SQL checks
- tshark packet decode smoke
- end-to-end single-file build + query smoke

## Required integration guarantees (current draft)

- embedded metadata includes required fields: `offset`, `size`, `ts_ns`, `linktype`
- required fields are query-compatible numeric types
- capture payload remains consumable by packet tools
- optional metadata fields may evolve without breaking required field semantics

Reference writer currently also emits SIP-friendly optional fields when present in capture decoding:

- `sip_call_id`
- `sip_method`
- `sip_status_code`
- `sip_cseq_method`
