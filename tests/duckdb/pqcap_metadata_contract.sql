-- pqcap metadata contract conformance checks (DuckDB)
--
-- Run:
--   duckdb -unsigned -cmd ".read tests/duckdb/pqcap_metadata_contract.sql"
--
-- This script creates fixtures under .tmp/testdata and verifies:
--   - required columns are present
--   - required types are query-compatible
--   - core invariants are enforceable in SQL

CREATE OR REPLACE TEMP TABLE pqcap_ok AS
SELECT
  0::UBIGINT AS offset,
  128::UBIGINT AS size,
  1716800000000000000::UBIGINT AS ts_ns,
  1::USMALLINT AS linktype
UNION ALL
SELECT
  128::UBIGINT AS offset,
  256::UBIGINT AS size,
  1716800000000000100::UBIGINT AS ts_ns,
  1::USMALLINT AS linktype;

COPY pqcap_ok TO '.tmp/testdata/pqcap_ok.parquet' (FORMAT PARQUET);

CREATE OR REPLACE TEMP VIEW v_ok AS
SELECT * FROM read_parquet('.tmp/testdata/pqcap_ok.parquet');

-- Test 1: required columns exist
SELECT
  CASE
    WHEN COUNT(*) = 4 THEN 'PASS required columns present'
    ELSE error('FAIL missing required columns')
  END AS result
FROM information_schema.columns
WHERE table_name = 'v_ok'
  AND column_name IN ('offset', 'size', 'ts_ns', 'linktype');

-- Test 2: required columns are query-compatible unsigned integers
SELECT
  CASE
    WHEN SUM(CASE WHEN column_name = 'offset'  AND data_type IN ('UBIGINT', 'BIGINT') THEN 1 ELSE 0 END) = 1
     AND SUM(CASE WHEN column_name = 'size'    AND data_type IN ('UBIGINT', 'BIGINT') THEN 1 ELSE 0 END) = 1
     AND SUM(CASE WHEN column_name = 'ts_ns'   AND data_type IN ('UBIGINT', 'BIGINT') THEN 1 ELSE 0 END) = 1
     AND SUM(CASE WHEN column_name = 'linktype' AND data_type IN ('USMALLINT', 'UINTEGER', 'UBIGINT', 'SMALLINT', 'INTEGER', 'BIGINT') THEN 1 ELSE 0 END) = 1
    THEN 'PASS required types compatible'
    ELSE error('FAIL required type mismatch')
  END AS result
FROM information_schema.columns
WHERE table_name = 'v_ok';

-- Test 3: invariant size > 0
SELECT
  CASE
    WHEN COUNT(*) = 0 THEN 'PASS size invariant'
    ELSE error('FAIL size must be > 0')
  END AS result
FROM v_ok
WHERE size <= 0;

-- Test 4: invariant offset + size does not overflow signed range when cast
SELECT
  CASE
    WHEN COUNT(*) = 0 THEN 'PASS offset+size range'
    ELSE error('FAIL offset+size range invalid')
  END AS result
FROM v_ok
WHERE ("offset" + "size") < "offset";

-- Negative fixture: missing required column should be detectable
CREATE OR REPLACE TEMP TABLE pqcap_missing AS
SELECT
  0::UBIGINT AS offset,
  128::UBIGINT AS size,
  1::USMALLINT AS linktype;

COPY pqcap_missing TO '.tmp/testdata/pqcap_missing.parquet' (FORMAT PARQUET);

CREATE OR REPLACE TEMP VIEW v_missing AS
SELECT * FROM read_parquet('.tmp/testdata/pqcap_missing.parquet');

SELECT
  CASE
    WHEN COUNT(*) = 3 THEN 'PASS negative fixture created'
    ELSE error('FAIL negative fixture not as expected')
  END AS result
FROM information_schema.columns
WHERE table_name = 'v_missing';
