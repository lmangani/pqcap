## sozip patterns to reuse in pqcap

`SOZip` is a strong companion reference for `pqcap`, especially for random seek inside compressed streams while preserving backward compatibility.

## What SOZip does well

### 1) Profile-not-new-format discipline

SOZip is explicitly a profile of ZIP, not a replacement format. That mindset is ideal for `pqcap`:

- keep existing ecosystem compatibility as a hard constraint
- layer performance features in a way old readers can ignore safely

### 2) Chunk-level random access in compressed payloads

SOZip forces periodic flush boundaries in Deflate and records chunk offsets in an index.
This gives true random-seek behavior without full decompression.

Transfer to `pqcap`:

- if packet payload blocks are compressed, chunk boundaries must be deterministic
- maintain an explicit mapping from logical offset windows to compressed offsets
- tune chunk size as a key performance/compression trade-off parameter

### 3) Side index as simple binary contract

SOZip uses a small binary index header + offset table with minimal fields:

- version
- chunk size
- offset width
- uncompressed/compressed sizes
- ascending chunk offsets

Transfer to `pqcap`:

- keep low-level index structures compact and parseable in C/Go/Rust/JS
- prefer fixed-width little-endian fields over complex nested metadata for bootstrap paths

### 4) Backward compatibility behavior testing

SOZip documents compatibility outcomes across many readers/writers, including edge behavior.
That kind of matrix is valuable for `pqcap`.

Transfer to `pqcap`:

- maintain a compatibility matrix for key packet tooling
- treat "writer rewrite behavior" (append-in-place vs rewrite) as a first-class risk

## What to adapt carefully (not copy directly)

- SOZip is ZIP + Deflate-specific; `pqcap` should stay PCAP-NG-centric.
- Hidden local-header-only index files are a ZIP trick; for `pqcap`, define an equivalent discovery path native to the chosen container strategy.
- SOZip solves random seek in one compressed file; `pqcap` must also model packet/session semantics and analytics metadata.

## pqcap-specific design implications

1. Define a compression-chunk profile only if compression is enabled.
2. Standardize chunk index integrity checks (monotonic offsets, in-range bounds).
3. Keep bootstrap metadata tiny and deterministic.
4. Add profile-level schemas for SIP/HEP fields separately from core chunk indexing.
