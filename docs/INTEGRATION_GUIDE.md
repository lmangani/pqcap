## Integration guide

This guide is for integrators who need two things at once:

1. packet-tool compatibility (`tshark`, Wireshark, protocol workflows)
2. query compatibility (DuckDB and Parquet tooling)

## Recommended path: DuckDB extension + pqcap CLI

The production integration surface is the **`pqcap_reader` DuckDB extension**, statically linked into the **`pqcap` CLI** in this repository.

| Plane | SQL | Shorthand |
|-------|-----|-----------|
| Metadata (Parquet index) | `read_pqcap(path)` | `SELECT * FROM 'file.pqcapng'` |
| Packets (full frames) | `read_pqcap_packets(path)` | `SELECT * FROM 'file.pcapng'` |

Helper scalars:

- `pqcap_offset_size(path)` — embedded Parquet byte range (`offset_length`)
- `pqcap_embed_index(path)` — copy-free index embed on an existing `.pcap`/`.pcapng`

### Index an existing capture (no payload duplication)

```bash
./dist/pqcap convert capture.pcapng indexed.pqcapng
```

Same as:

1. Copy capture bytes unchanged
2. `SELECT pqcap_embed_index('indexed.pqcapng')`

Embedded Parquet stores searchable features (`offset`, `size`, flow fields, timestamps). Payloads remain in the PCAP-NG plane and are read via `read_pqcap_packets` when needed.

### Filter metadata, then fetch payloads

```sql
WITH hits AS (
  SELECT src_ip, src_port, dst_ip, dst_port
  FROM read_pqcap('indexed.pqcapng')
  WHERE dst_port = 5060 AND protocols LIKE '%udp%'
)
SELECT p.timestamp_micros, p.src_ip, p.dst_port, p.payload
FROM read_pqcap_packets('indexed.pqcapng') AS p
JOIN hits USING (src_ip, src_port, dst_ip, dst_port)
LIMIT 100;
```

### Repack or filter packets (requires payload in COPY)

When rewriting packet bytes, use `COPY ... (FORMAT pcapng, mode 'pqcap')`. `payload` is required to write EPB blocks; Parquet still stores features only.

## Legacy / prototype paths

### Shell script writer

```bash
bash scripts/pqcap_from_pcap.sh input.pcapng output.pqcapng
```

### Parameterized query script

```bash
bash scripts/pqcap_query.sh output.pqcapng "protocols LIKE '%udp%'"
```

### Python in-memory prototype

```bash
python3 scripts/pqcap_duckdb_query.py output.pqcapng \
  --sql "SELECT frame_number, protocols, \"size\" FROM pqcap_meta LIMIT 20"
```

Remote/object read using byte ranges:

```bash
python3 scripts/pqcap_duckdb_query.py "https://example.org/path/capture.pqcapng" \
  --sql "SELECT COUNT(*) AS n FROM pqcap_meta"
```

Extract embedded Parquet to a sidecar (debug only):

```bash
python3 scripts/pqcap_embedded_metadata.py extract output.pqcapng extracted_metadata.parquet
```

## Metadata schema (reference writer)

**Required** (see `SPEC.md`): `offset`, `size`, `ts_ns`, `linktype`

**Optional index fields** commonly emitted by `pqcap_reader`: `frame_number`, `protocols`, `src_ip`, `dst_ip`, `src_port`, `dst_port`, `interface_id`, `data_link`, `captured_length`, `orig_len`, `comment`

## Packet reader schema (`read_pqcap_packets`)

Classic `.pcap` and `.pcapng` inputs:

| Column | Type | Notes |
|--------|------|-------|
| `timestamp_micros` | `BIGINT` | Packet timestamp |
| `interface_id` | `UBIGINT` | PCAP-NG interface |
| `data_link` | `USMALLINT` | DLT / link type |
| `captured_length` | `UBIGINT` | Captured bytes |
| `orig_len` | `UBIGINT` | Wire length |
| `comment` | `VARCHAR` | EPB comment if any |
| `src_ip`, `dst_ip` | `VARCHAR` | Parsed when decodable (Ethernet/RAW/SLL) |
| `src_port`, `dst_port` | `INTEGER` | L4 ports when present |
| `l4_protocol` | `VARCHAR` | e.g. `UDP`, `TCP`, `ICMP` |
| `payload` | `BLOB` | Full captured frame bytes |

## Packet-tool verification

```bash
tshark -r output.pqcapng -c 10
```

Indexed captures remain readable as PCAP-NG by standard tools.

## Conformance checks

Run all tests:

```bash
bash tests/run_all.sh
```

Extension-focused smoke:

```bash
bash tests/extension/smoke_build_and_query.sh
```

Release gate:

```bash
make release-check
```

## Required integration guarantees (current draft)

- embedded metadata includes required fields: `offset`, `size`, `ts_ns`, `linktype`
- required fields are query-compatible numeric types
- capture payload remains consumable by packet tools
- optional metadata fields may evolve without breaking required field semantics
- Parquet metadata does not duplicate packet payloads; payloads are fetched from the capture plane

Reference writer also emits SIP-friendly optional fields when present in capture decoding:

- `sip_call_id`
- `sip_method`
- `sip_status_code`
- `sip_cseq_method`
