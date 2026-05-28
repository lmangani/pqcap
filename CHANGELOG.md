# Changelog

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
