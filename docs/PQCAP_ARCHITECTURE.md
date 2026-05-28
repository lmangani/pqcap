## pqcap architecture draft (v0)

This is a first draft architecture derived from `cozip` principles, adapted to network capture workloads.

## Objectives

- Preserve packet-tool interoperability expectations.
- Provide remote random access via byte ranges.
- Provide Parquet-native metadata for SQL/dataframe filters.
- Make metadata directly queryable from DuckDB and compatible Parquet readers without custom rewrite steps.
- Support high-scale telecom/network workflows (SIP, HEP, RTP, signaling observability).

## Proposed core model

`pqcap` file = capture payload + deterministic metadata plane.

Design input sources:

- `cozip`: byte-0 bootstrap + Parquet-first manifest/query path
- `sozip`: chunked-compression seek index pattern and compatibility discipline

### Core sections

1. **Bootstrap header**
   - fixed-position minimal structure for fast discovery
   - fields: magic, binary version, profile id, pointer(s) to metadata blocks, integrity slot
2. **Packet data region**
   - packet bytes and packet headers (PCAP-NG-compatible strategy to be finalized)
3. **Metadata region**
   - Parquet manifest(s) describing packet/session byte ranges and optional higher-level attributes
4. **Tail anchor**
   - small trailing structure for fast tail validation and integrity coverage

## Reader flow (remote-friendly)

1. Range-read bootstrap header.
2. Validate version/profile and structural integrity.
3. Range-read metadata Parquet block(s).
4. Query metadata locally (DuckDB/Arrow/Polars/etc).
5. Range-read only matching packet byte ranges from the payload region.

## Query interoperability requirement

`pqcap` treats query interoperability as a core requirement:

- metadata files must be valid Parquet consumable by standard engines
- required columns and logical types must be stable and documented
- schema evolution must preserve backward-compatible reads for DuckDB-first workflows
- optimized readers may add convenience columns, but must not break baseline Parquet readability

## Metadata schema layers

### Required core columns (draft)

- `offset` (`uint64`): packet or packet-chunk payload offset
- `size` (`uint32` or `uint64`): payload byte length
- `ts_ns` (`uint64`): normalized timestamp
- `linktype` (`uint16`): capture link type where relevant

### Optional network profile columns (draft)

- `src_ip`, `dst_ip`, `src_port`, `dst_port`, `proto`
- `vlan`, `ip_tos`, `tcp_flags`
- `sip_call_id`, `sip_method`, `sip_status`
- `hep_capture_id`, `hep_correlation_id`

## Profiles (initial proposal)

- `0`: none (generic packet indexing only)
- `1`: flow profile (5-tuple + timing oriented)
- `2`: SIP/HEP profile (Homer/qxip-centric columns)

Profiles must not alter core binary rules; they only constrain metadata naming/schema and semantics.

## Writer invariants (draft)

- All indexed offsets/sizes are final before writing bootstrap.
- Post-finalization mutation is restricted to one integrity field.
- Duplicate logical ids and invalid names are rejected deterministically.
- Canonical error codes are emitted for validation failures.

## Early implementation plan

1. **Spec skeleton**
   - `SPEC.md` with normative terms, layout, invariants, error codes.
2. **Reference writer core**
   - deterministic planning + serialize + finalize + integrity patch.
3. **Reference reader**
   - minimal HTTP range reader + metadata parser.
4. **Tool integrations**
   - DuckDB table function
   - DuckDB SQL examples and conformance tests against required columns/types
   - Python API for `read()` and `write()`
   - validation CLI (`pqcap validate`)

## Open decisions

- exact PCAP-NG compatibility strategy (pure extension blocks vs sidecar-in-container approach)
- integrity hash algorithm and coverage window
- single manifest vs partitioned manifests for multi-terabyte captures
- profile registration governance and versioning policy
- compression mode policy (store-only baseline vs optional chunked-compression profile inspired by SOZip)
