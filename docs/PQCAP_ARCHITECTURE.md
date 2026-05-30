## pqcap architecture (v0.1 RC)

Hybrid capture format: **PCAP-NG packet plane** + **embedded Parquet metadata** + **footer locator** for range-read discovery.

## Objectives

- Preserve packet-tool interoperability (Wireshark / `tshark`).
- Provide remote random access via byte ranges on object storage.
- Provide Parquet-native metadata for SQL filters and joins.
- Keep one portable artifact (no sidecar index files).
- Support two-phase retrieval: filter in metadata, read payloads only for hits.

## On-disk layout (current implementation)

Each `.pqcapng` (or indexed `.pcapng`) contains:

1. **Packet region** — standard PCAP-NG blocks (SHB, IDB, EPB, …). Packet bytes are unchanged from the source capture when using `pqcap convert` / `pqcap_embed_index`.
2. **Metadata block** — PCAP-NG custom block (`0x00000BAD`) holding enterprise id, magic `PQCAPMETA`, version, and raw Parquet bytes.
3. **Footer locator** — fixed 44-byte final custom block (`0x00000BEE`) with magic `PQCAPFTR`, `metadata_parquet_offset`, and `metadata_parquet_length`.

Readers discover metadata with a single tail range-read, then range-read only the embedded Parquet span via `pqcap-subfile://`.

## Query planes

| Plane | Reader | Contents |
|-------|--------|----------|
| Metadata | `read_pqcap` → `read_parquet('pqcap-subfile://…')` | Index columns only (no payloads) |
| Packets | `read_pqcap_packets` (LightPcapNg + classic PCAP) | Headers + full frame `payload` BLOB |

DuckDB **replacement scans** route quoted paths by suffix: `.pqcap`/`.pqcapng` → metadata; `.pcap`/`.pcapng` → packets.

## Writer paths

| Operation | Use when |
|-----------|----------|
| `pqcap convert` / `pqcap_embed_index` | Index existing capture; no packet re-encoding |
| `COPY … mode 'pcapng'` | Filter/repack to plain PCAP-NG |
| `COPY … mode 'pqcap'` | Filter/repack packets **and** embed index (`payload` required for EPB write) |

## Metadata schema layers

### Required core columns

See `SPEC.md`: `offset`, `size`, `ts_ns`, `linktype`

### Reference optional columns

`frame_number`, `protocols`, five-tuple fields, PCAP-NG header fields (`interface_id`, `data_link`, `captured_length`, `orig_len`, `comment`)

### Future profile columns (draft)

- SIP/HEP: `sip_call_id`, `sip_method`, `sip_status`, `hep_capture_id`, …
- Profiles constrain optional naming only; core binary rules stay fixed.

## Reader flow (remote-friendly)

1. Range-read last 44 bytes (footer locator).
2. Parse `metadata_parquet_offset` / `metadata_parquet_length`.
3. Range-read embedded Parquet; query with projection/filter pushdown.
4. For survivors, range-read or stream packet bytes from EPB offsets (`offset`/`size` in metadata).

## Implementation map

| Component | Location |
|-----------|----------|
| Format spec | `SPEC.md` |
| DuckDB extension | `duckdb_pqcap_reader/` submodule |
| CLI | `cli/pqcap_main.cpp` |
| Prototype scripts | `scripts/pqcap_*.py`, `scripts/pqcap_from_pcap.sh` |

## Open decisions

- Integrity hash coverage window
- Partitioned manifests for multi-terabyte metadata
- Profile registration and versioning policy
- Optional compression profile (SOZip-inspired) for cold storage
