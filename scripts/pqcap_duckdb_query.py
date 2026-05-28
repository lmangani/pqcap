#!/usr/bin/env python3
import argparse
import urllib.request
from pathlib import Path

import duckdb
import pyarrow.parquet as pq
from pyarrow import BufferReader

from pqcap_embedded_metadata import FOOTER_BLOCK_SIZE, extract_metadata_bytes, parse_footer


def _is_http_url(v: str) -> bool:
    return v.lower().startswith("http://") or v.lower().startswith("https://")


def _fetch_http_range(url: str, start: int | None, end: int | None, suffix_len: int | None = None) -> bytes:
    headers = {}
    if suffix_len is not None:
        headers["Range"] = f"bytes=-{suffix_len}"
    elif start is not None and end is not None:
        headers["Range"] = f"bytes={start}-{end}"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as resp:
        return resp.read()


def _extract_metadata_bytes_http(url: str) -> bytes:
    footer = _fetch_http_range(url, None, None, suffix_len=FOOTER_BLOCK_SIZE)
    parsed = parse_footer(footer)
    if parsed is None:
        raise SystemExit("FAIL: pqcap footer not found or unsupported")
    parquet_offset, parquet_len = parsed
    if parquet_len == 0:
        raise SystemExit("FAIL: embedded metadata length is zero")
    end = parquet_offset + parquet_len - 1
    return _fetch_http_range(url, parquet_offset, end)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Query embedded pqcap metadata without extracting to disk."
    )
    parser.add_argument("pqcap_file", help="Input .pqcapng file")
    parser.add_argument(
        "--sql",
        default=(
            "SELECT frame_number, ts_ns, protocols, src_ip, src_port, dst_ip, dst_port, "
            "\"offset\", \"size\" FROM pqcap_meta ORDER BY frame_number LIMIT 50"
        ),
        help="SQL query to execute; table name is pqcap_meta",
    )
    args = parser.parse_args()

    if _is_http_url(args.pqcap_file):
        metadata_bytes = _extract_metadata_bytes_http(args.pqcap_file)
    else:
        pqcap_path = Path(args.pqcap_file)
        if not pqcap_path.exists():
            raise SystemExit(f"FAIL: pqcap file not found: {pqcap_path}")
        metadata_bytes = extract_metadata_bytes(pqcap_path)
        if metadata_bytes is None:
            raise SystemExit("FAIL: embedded metadata block not found")

    table = pq.read_table(BufferReader(metadata_bytes))
    con = duckdb.connect()
    con.register("pqcap_meta", table)
    cur = con.execute(args.sql)
    cols = [d[0] for d in cur.description]
    rows = cur.fetchall()
    print("\t".join(cols))
    for row in rows:
        print("\t".join("" if v is None else str(v) for v in row))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
