# Changelog

## Unreleased

### Added

- **`read_pqcap_packets`** — classic `.pcap` and `.pcapng` reader with 12-column schema including full-frame `payload` BLOB.
- **`pqcap_embed_index(path)`** — embed searchable Parquet metadata on an existing capture without re-encoding packets.
- **`pqcap convert`** CLI command — copy capture bytes, then embed feature-only index.
- **`COPY … (FORMAT pcapng, mode 'pqcap')`** — repack/filter with embedded metadata (Parquet holds search features, not payloads).
- DuckDB **replacement scans** for `.pqcap`, `.pqcapng`, `.pcap`, `.pcapng` paths.
- Extension SQL tests with Wireshark sample fixtures (SIP/PPPoE, RTP, large HTTPS trace).
- Updated format docs: optional metadata columns, packet-plane schema, integration guide.

### Fixed

- `COPY mode 'pqcap'` finalize when overwriting an existing file (DuckDB `use_tmp_file` temp-path resolution).

## 0.1.0-rc1

Initial release candidate focused on practical interoperability and validation.

### Added

- Draft `SPEC.md` with normative metadata contract and validation requirements.
- `scripts/pqcap_from_pcap.sh` to produce a practical single-file `.pqcapng` artifact with embedded metadata.
- `scripts/pqcap_query.sh` for parameterized DuckDB querying.
- End-to-end example workflow in `examples/`.
- Integrator documentation in `docs/INTEGRATION_GUIDE.md`.
- Conformance and smoke tests:
  - DuckDB metadata contract SQL checks
  - packet-tool compatibility smoke via `tshark`
  - full `tests/run_all.sh` orchestration

### Validation status

- Full local suite passes with:
  - `duckdb`
  - `tshark` / `text2pcap`
