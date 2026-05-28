## Release process (practical)

Current target release: `0.1.0-rc1`.

## Prerequisites

- `duckdb`
- `tshark`
- `text2pcap`

## Release gate

Run:

```bash
make release-check
```

This must pass before tagging a release candidate.

## What release-check verifies

1. Example `.pqcapng` generation from a real capture fixture.
2. File validation (`scripts/pqcap_validate.sh`) against:
   - packet decode viability (`tshark`)
   - metadata required columns and invariants (`duckdb`)
3. Full project test suite (`tests/run_all.sh`).

## Integrator acceptance checklist

- Can build a `.pqcapng` file from pcap/pcapng input.
- Can query metadata in DuckDB without custom transforms.
- Can read resulting `.pqcapng` file with packet tools.
- Can run one-command validation for produced file.
