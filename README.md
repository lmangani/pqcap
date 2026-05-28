<img width="300" alt="pqcap" src="https://github.com/user-attachments/assets/bcc8c286-1d67-4c5e-baa9-6e7342709879" />

# pqcap

One file, two query planes: **PCAP-NG packets + embedded Parquet metadata**.

`pqcap` is a practical bridge between packet tooling and analytics tooling.  
You keep standard packet compatibility (`tshark`, Wireshark ecosystem) while getting SQL-native filtering and joins from the same `.pqcapng` object.

Under the hood, this works by embedding Parquet metadata in PCAP-NG custom blocks plus a fixed-size footer locator block, so readers can discover and range-read the metadata plane efficiently.

Because that metadata plane is standard Parquet, readers inherit projection/filter pushdown and Parquet-style range reads, enabling optimized partial fetch on object stores like S3 instead of downloading full capture files.

Current release candidate: `0.1.0-rc1`.

## Why this exists

Traditional workflows often force a tradeoff:

- Keep raw packet fidelity, but analytics are slow and expensive.
- Build separate analytics indexes, but now storage and lifecycle split.

`pqcap` removes that split:

- **Single artifact**: packet bytes and metadata stay together.
- **PCAP-NG compatible**: still readable as capture data by standard tools.
- **DuckDB queryable**: metadata and packet-derived fields are SQL-visible.
- **Remote-friendly**: footer locator supports deterministic range reads.

## Mental model

Each `.pqcapng` contains:

- **Packet plane**: normal PCAP-NG capture records.
- **Parquet plane**: embedded metadata index (`offset`, `size`, protocol/flow fields, timestamps, etc.).

Typical workflow:

1. Filter quickly in Parquet metadata.
2. Read packet payload only for matching candidates.
3. Keep one portable file for exchange, archive, and replay.

## pqcap CLI

`pqcap` is a thin control utility over a static DuckDB engine with the `pqcap_reader` extension preloaded.  
It lives in this repository (`cli/`), not in the extension submodule.

`query` runs one SQL statement. `shell` opens the interactive DuckDB session (full engine underneath).

### Install prebuilt binary (recommended)

Published [GitHub Releases](https://github.com/sipcapture/pqcap/releases) ship one executable per platform (not a zip). Pick your asset and install with `curl`:

**Linux (x86_64)**

```bash
curl -fsSL -o pqcap \
  "https://github.com/sipcapture/pqcap/releases/latest/download/pqcap-linux-amd64"
chmod +x pqcap
./pqcap version
```

**macOS (Apple Silicon)**

```bash
curl -fsSL -o pqcap \
  "https://github.com/sipcapture/pqcap/releases/latest/download/pqcap-macos-arm64"
chmod +x pqcap
./pqcap version
```

Optional: install on your `PATH`:

```bash
sudo install -m 755 pqcap /usr/local/bin/pqcap
```

Pin a specific version by replacing `latest` with a tag, e.g. `.../releases/download/v0.1.0/pqcap-linux-amd64`.

### Build from source

```bash
make pqcap-cli
./dist/pqcap version
```

Example:

```bash
./dist/pqcap query -c "SELECT COUNT(*) FROM read_pqcap('.tmp/examples/demo.pqcapng')"
./dist/pqcap shell
```

### Releases (maintainers)

Create and **publish** a GitHub Release (tag + notes). Publishing runs [`.github/workflows/release.yml`](.github/workflows/release.yml), which uploads raw binaries:

| Asset | Platform |
|-------|----------|
| `pqcap-linux-amd64` | Linux x86_64 |
| `pqcap-macos-arm64` | macOS Apple Silicon |

## Explore with DuckDB

You can use either the **pqcap CLI** (above) or a **DuckDB build with the extension** (below).

### Prerequisites

- `tshark` and `text2pcap` (for building example captures and validation scripts)
- for CLI: prebuilt `pqcap` or `make pqcap-cli`
- for extension-only: `make` and a local build of `duckdb_pqcap_reader`

Create demo data and open the engine:

```bash
bash examples/build_bundle_example.sh
make pqcap-cli
./dist/pqcap shell
```

Or use the extension build directly:

```bash
make -C duckdb_pqcap_reader release
./duckdb_pqcap_reader/build/release/duckdb -unsigned
```

### Metadata-first flow discovery

Use the embedded Parquet plane to scan flows and ports quickly.  
This is the cheapest way to understand capture shape before touching payload bytes.

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

CLI equivalent:

```bash
./dist/pqcap query -c "SELECT frame_number, protocols, src_ip, dst_port FROM read_pqcap('.tmp/examples/demo.pqcapng') LIMIT 10"
```

### Packet-plane protocol slicing

Read packet records directly and apply protocol-level predicates.  
This shows the packet-compatible view with SQL ergonomics.

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

### Cross-plane enrichment

Join metadata and packet-derived fields in one query to compare indexed metadata with decoded packet attributes.

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

### Two-phase retrieval (index then payload)

Use metadata as a narrow phase, then materialize payload only for matching traffic.  
This is the main performance pattern for larger captures.

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

This is the intended high-scale pattern: use embedded Parquet to reduce work, then touch packet bytes for the survivors.

## Write captures from DuckDB

The extension now supports writing captures with:

- `FORMAT pcapng, mode 'pcapng'`: packet-plane output only
- `FORMAT pcapng, mode 'pqcap'`: packet plane + embedded Parquet metadata plane

### Export packet-compatible output (`mode 'pcapng'`)

Use this when you want filtered/repacked capture output that stays pure PCAP-NG.

```sql
COPY (
  SELECT
    timestamp_micros,
    orig_len,
    payload,
    src_ip,
    src_port,
    dst_ip,
    dst_port,
    l4_protocol
  FROM read_pqcap_packets('.tmp/examples/demo.pqcapng')
) TO 'out.pcapng' (FORMAT pcapng, mode 'pcapng');
```

### Export hybrid analytics-ready output (`mode 'pqcap'`)

Use this when you want a single artifact that is both packet-tool readable and metadata-queryable.

```sql
COPY (
  SELECT
    timestamp_micros,
    orig_len,
    payload,
    src_ip,
    src_port,
    dst_ip,
    dst_port,
    l4_protocol
  FROM read_pqcap_packets('.tmp/examples/demo.pqcapng')
) TO 'out.pqcapng' (FORMAT pcapng, mode 'pqcap');
```

## Packet-tool compatibility

Inspect the same file with `tshark`:

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

## Optional Python path

For quick metadata iteration (without extension SQL):

```bash
python3 scripts/pqcap_duckdb_query.py .tmp/examples/demo.pqcapng --sql "SELECT frame_number, protocols, \"size\" FROM pqcap_meta LIMIT 10"
```

## Caveats (current RC)

- Packet-plane joins for some RAW-IP cases still depend on decode coverage in `read_pqcap_packets`.
- `pqcap` format is draft/RC and still tightening around writer/reader conformance checks.

## Documentation map

- Format contract: `SPEC.md`
- Integration details: `docs/INTEGRATION_GUIDE.md`
- Release process: `docs/RELEASE.md`
- Architecture notes: `docs/PQCAP_ARCHITECTURE.md`
