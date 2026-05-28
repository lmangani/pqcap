## cozip patterns to reuse in pqcap

This note captures the `cozip` design choices that should carry directly into `pqcap`.

### 1) Compatibility-first container strategy

`cozip` remains a valid ZIP while adding a deterministic fast path. This is the most important idea:

- do not break existing readers
- embed optimization as an additive contract

For `pqcap`, the equivalent target is:

- remain PCAP-NG compatible for baseline tooling assumptions
- add a deterministic, spec-defined metadata/index access path for optimized readers

### 2) Deterministic byte-0 bootstrap

`cozip` pins a fixed bootstrap structure at the beginning of the archive so a reader can:

1. fetch a tiny first range
2. discover where richer metadata lives
3. avoid scanning the full object

Transfer to `pqcap`:

- define a fixed-size or quickly-parseable bootstrap region near byte 0
- include version + profile + pointers/offsets to metadata blocks

### 3) Strict writer invariants

`cozip` succeeds because the writer model is strict and deterministic:

- planned offsets before write
- immutable structure after finalize
- only one allowed post-write mutation (integrity hash bytes)

Transfer to `pqcap`:

- require full precomputed layout for indexed blocks
- define exactly what may be mutated after payload write (ideally one integrity slot)
- prohibit ambiguous features that break range determinism

### 4) Integrity check scoped to access path

`cozip` hashes bootstrap index + trailing archive window to detect structural drift quickly.

Transfer to `pqcap`:

- integrity coverage should prioritize fields needed for random access
- verify cheaply before trusting offsets
- standardize canonical error codes

### 5) Profile mechanism above core

`cozip` cleanly separates:

- core binary format rules
- optional domain profiles (Flat, TACO)

Transfer to `pqcap`:

- keep a stable core
- add profiles for network workloads (for example SIP/HEP-centric schemas)
- reserve profile ids and define forward-compat behavior

### 6) Language split: one writer core, many bindings

`cozip` uses one C writer core wrapped by higher-level bindings.

Transfer to `pqcap`:

- single reference writer core to keep byte-level output identical
- thin language bindings for Python/Go/Rust/JS readers and ingestion tools

### 7) Minimal remote reader bootstrap sequence

`cozip` readers do:

1. read bootstrap bytes
2. parse index
3. fetch metadata Parquet
4. query rows and range-fetch payload bytes

This exact access pattern should be retained for `pqcap` readers.

## Practical implications for pqcap

- The first spec milestone should be on-disk invariants and deterministic layout, not API shape.
- The second milestone should be a tiny bootstrap reader over HTTP ranges.
- The third milestone should be profile-specific network metadata schemas.
