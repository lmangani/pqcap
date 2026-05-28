<img width="300" alt="pqcap" src="https://github.com/user-attachments/assets/bcc8c286-1d67-4c5e-baa9-6e7342709879" />

# pqcap

One file, two query planes: PCAP-NG packets + embedded Parquet metadata.

`pqcap` keeps packet-tool compatibility while adding SQL-native analytics from the same `.pqcapng` artifact.

Current release candidate: `0.1.0-rc1`.

## Why pqcap

- **Single-file hybrid**: packet bytes and query metadata travel together.
- **Packet fidelity**: the file remains valid PCAP-NG for tools like `tshark`.
- **DuckDB-native SQL**: query metadata and packet-derived fields through the extension.
- **Remote-friendly metadata path**: readers can locate embedded metadata via fixed footer and fetch ranges.

## File model

Each `.pqcapng` contains:

- **Packet plane**: standard PCAP-NG capture records
- **Parquet plane**: embedded metadata index (offset/size, protocol fields, SIP fields, etc.)

## DuckDB-first quickstart

### Prerequisites

- `duckdb`
- `tshark` and `text2pcap`
- `make`

### 1) Build a sample `.pqcapng`

```bash
bash examples/build_bundle_example.sh
```

Output: `.tmp/examples/demo.pqcapng`

### 2) Build the DuckDB extension

```bash
make -C duckdb_pqcap_reader release
```

### 3) Open DuckDB once

```bash
./duckdb_pqcap_reader/build/release/duckdb -unsigned
```

### 4) Query metadata plane (Parquet in same file)

```sql
SELECT
  frame_number,
  protocols,
  src_ip,
  src_port,
  dst_ip,
  dst_port,
  "offset",
  "size"
FROM read_pqcap('.tmp/examples/demo.pqcapng');
```

### 5) Query packet plane (PCAP in same file)

```sql
SELECT
  timestamp_micros,
  src_ip,
  dst_ip,
  src_port,
  dst_port,
  l4_protocol,
  orig_len
FROM read_pqcap_packets('.tmp/examples/demo.pqcapng')
WHERE l4_protocol = 'UDP';
```

### 6) Combine both planes in one SQL workflow

```sql
WITH meta AS (
  SELECT
    frame_number,
    ts_ns,
    protocols,
    src_ip,
    src_port,
    dst_ip,
    dst_port,
    "size"
  FROM read_pqcap('.tmp/examples/demo.pqcapng')
),
pkt AS (
  SELECT
    timestamp_micros,
    src_ip,
    src_port,
    dst_ip,
    dst_port,
    l4_protocol,
    orig_len
  FROM read_pqcap_packets('.tmp/examples/demo.pqcapng')
)
SELECT
  meta.frame_number,
  meta.protocols,
  pkt.l4_protocol,
  meta."size" AS meta_size,
  pkt.orig_len AS packet_orig_len
FROM meta
JOIN pkt USING (src_ip, src_port, dst_ip, dst_port)
LIMIT 10;
```

### 7) Use Parquet index as a join filter to extract payloads

Use the metadata plane as a fast pre-filter, then join to packet-plane rows to
retrieve payload bytes only for matching traffic.

```sql
WITH indexed_flows AS (
  SELECT
    src_ip,
    src_port,
    dst_ip,
    dst_port
  FROM read_pqcap('.tmp/examples/demo.pqcapng')
  WHERE dst_port = 5678
    AND protocols LIKE '%udp%'
  GROUP BY src_ip, src_port, dst_ip, dst_port
)
SELECT
  p.timestamp_micros,
  p.src_ip,
  p.src_port,
  p.dst_ip,
  p.dst_port,
  p.l4_protocol,
  p.orig_len,
  p.payload
FROM read_pqcap_packets('.tmp/examples/demo.pqcapng') AS p
JOIN indexed_flows AS f
  ON p.src_ip = f.src_ip
 AND p.src_port = f.src_port
 AND p.dst_ip = f.dst_ip
 AND p.dst_port = f.dst_port
ORDER BY p.timestamp_micros
LIMIT 100;
```

This pattern is the intended fast path: narrow candidates in embedded Parquet,
then materialize payloads from the packet plane only for those candidate flows.

Note: SIP/5060 filtering is supported in metadata now; matching packet-plane
SIP joins depend on RAW-IP packet decode coverage in `read_pqcap_packets`.

## Packet-tool compatibility

Inspect the same file directly with `tshark`:

```bash
tshark -r .tmp/examples/demo.pqcapng -c 10
```

## Validation and tests

Run extension + project smoke tests:

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

## Optional Python native path

For quick metadata iteration (without extension SQL):

```bash
python3 scripts/pqcap_duckdb_query.py .tmp/examples/demo.pqcapng --sql "SELECT frame_number, protocols, \"size\" FROM pqcap_meta LIMIT 10"
```

## Documentation map

- Format contract: `SPEC.md`
- Integration details: `docs/INTEGRATION_GUIDE.md`
- Release process: `docs/RELEASE.md`
- Architecture notes: `docs/PQCAP_ARCHITECTURE.md`
