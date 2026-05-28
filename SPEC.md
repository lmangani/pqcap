# PQCAP Format Specification

**Version** 0.1-draft  
**Status** Draft

---

## 1. Scope

This document defines the core `pqcap` format contract:

- PCAP-NG compatible capture behavior
- deterministic metadata discovery for optimized readers
- Parquet metadata contract that is directly queryable by DuckDB and other Parquet readers

This draft focuses on the metadata/query contract first, with binary-layout details to follow.

## 2. Conformance language

The key words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY** are normative.

## 3. Core requirements

1. A `pqcap` object **MUST** preserve baseline packet-tool interoperability expectations.
2. A `pqcap` object **MUST** expose metadata as standard Parquet.
3. Parquet metadata **MUST** be readable by DuckDB without custom rewrite or transformation.
4. Optimized readers **MAY** add computed convenience fields at runtime, but on-disk Parquet **MUST** remain standards-compliant.
5. A conforming writer **MUST** include a fixed-size footer locator that allows readers to locate embedded Parquet metadata with range reads, without downloading the full capture object.

## 3.1 Footer locator (draft)

Current draft locator is a fixed-size 44-byte final PCAP-NG custom block.

Inside the block body:

- `enterprise_id` (uint32 LE)
- `magic` (8 bytes): `PQCAPFTR`
- `version` (uint16 LE)
- `reserved` (uint16 LE)
- `metadata_parquet_offset` (uint64 LE)
- `metadata_parquet_length` (uint64 LE)

Reader flow for remote/object storage:

1. range-read last 44 bytes
2. parse footer and locate embedded Parquet
3. range-read only embedded Parquet bytes
4. query metadata and fetch packet ranges of interest

## 3.2 Large-object requirements

`pqcap` is intended to support very large captures and very large metadata tables.

1. `metadata_parquet_offset` **MUST** be encoded as unsigned 64-bit.
2. `metadata_parquet_length` **MUST** be encoded as unsigned 64-bit.
3. Writers **MUST** support metadata lengths larger than 4 GiB.
4. Readers **MUST** validate `metadata_parquet_offset + metadata_parquet_length` without overflow and reject invalid values.
5. Reader discovery of embedded metadata **MUST** be possible from fixed-size trailer bytes (range-read friendly) without fetching full object bytes.
6. Metadata row counts **MAY** range from a few rows to millions of rows (or more); readers **SHOULD** rely on Parquet projection/filtering and avoid materializing unneeded columns.

## 4. Metadata Parquet contract (v0.1)

`pqcap` metadata represents packet (or packet-chunk) locations in the capture payload.

### 4.1 Required columns

The metadata Parquet file **MUST** contain these columns:

- `offset` (`UINT64`): byte offset in capture payload space
- `size` (`UINT64`): byte length in capture payload space
- `ts_ns` (`UINT64`): normalized packet timestamp in nanoseconds
- `linktype` (`UINT16` or compatible unsigned integer width)

### 4.2 Column rules

1. `offset` **MUST** be greater than or equal to 0.
2. `size` **MUST** be greater than 0.
3. `offset + size` **MUST** not overflow unsigned 64-bit arithmetic.
4. `ts_ns` **SHOULD** be monotonic non-decreasing within a writer-defined packet ordering.
5. `linktype` values **SHOULD** map to known link-layer type codes where applicable.

### 4.3 Optional columns

Writers **MAY** include additional domain columns (for example flow, SIP, or HEP fields). Optional columns **MUST NOT** change the meaning of required columns.

### 4.4 Compatibility guarantees

1. Schema evolution **MUST** keep required columns stable by name and meaning.
2. Required columns **MUST NOT** be dropped or repurposed in a minor format revision.
3. Readers that only understand required columns **MUST** still be able to query conforming metadata.

### 4.5 Scale guidance (normative + practical)

1. Writers **SHOULD** emit Parquet row groups sized for query pruning (for example, not a single giant row group for multi-million-row metadata).
2. Writers **SHOULD** include statistics in Parquet metadata where possible to improve predicate pushdown.
3. Readers **SHOULD** project only required columns for packet range planning (`offset`, `size`, and relevant filters).

## 5. Validation requirements

A conforming implementation **SHOULD** provide a validation mode that checks:

- required columns exist
- required columns are of compatible numeric types
- row-level invariants (`size > 0`, overflow safety)

## 6. Canonical error names (draft)

- `MISSING_REQUIRED_COLUMN`
- `INVALID_REQUIRED_TYPE`
- `INVALID_SIZE_VALUE`
- `OFFSET_SIZE_OVERFLOW`
- `UNSUPPORTED_SCHEMA_VERSION`

## 7. Testability requirement

Every normative requirement in section 4 and section 5 **SHOULD** be covered by executable conformance tests.

The initial DuckDB conformance tests are defined in `tests/duckdb/pqcap_metadata_contract.sql`.
