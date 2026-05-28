#!/usr/bin/env python3
import struct
import sys
from pathlib import Path


CUSTOM_BLOCK_TYPE = 0x00000BAD
FOOTER_BLOCK_TYPE = 0x00000BEE
ENTERPRISE_ID = 0x51584950  # "QXIP"
MAGIC = b"PQCAPMETA"
VERSION = 1
FOOTER_MAGIC = b"PQCAPFTR"
FOOTER_VERSION = 1
FOOTER_BODY_SIZE = 32
FOOTER_BLOCK_SIZE = 44


def _pad4(data: bytes) -> bytes:
    pad = (-len(data)) % 4
    if pad:
        return data + (b"\x00" * pad)
    return data


def append_metadata_block(capture_path: Path, parquet_path: Path, output_path: Path) -> None:
    capture = capture_path.read_bytes()
    parquet = parquet_path.read_bytes()

    body = bytearray()
    body += struct.pack("<I", ENTERPRISE_ID)
    body += MAGIC
    body += struct.pack("<H", VERSION)
    body += struct.pack("<H", 0)  # reserved
    body += struct.pack("<Q", len(parquet))
    body += parquet
    body = bytearray(_pad4(bytes(body)))

    total_len = 12 + len(body)
    block = struct.pack("<I", CUSTOM_BLOCK_TYPE) + struct.pack("<I", total_len) + bytes(body) + struct.pack("<I", total_len)
    block_start = len(capture)
    parquet_abs_offset = block_start + 8 + 25
    parquet_len = len(parquet)
    footer_body = struct.pack(
        "<I8sHHQQ",
        ENTERPRISE_ID,
        FOOTER_MAGIC,
        FOOTER_VERSION,
        0,  # reserved
        parquet_abs_offset,
        parquet_len,
    )
    footer_total_len = 12 + len(footer_body)
    footer_block = (
        struct.pack("<I", FOOTER_BLOCK_TYPE)
        + struct.pack("<I", footer_total_len)
        + footer_body
        + struct.pack("<I", footer_total_len)
    )

    output_path.write_bytes(capture + block + footer_block)


def parse_footer(footer_bytes: bytes) -> tuple[int, int] | None:
    if len(footer_bytes) != FOOTER_BLOCK_SIZE:
        return None
    block_type, total_len = struct.unpack_from("<II", footer_bytes, 0)
    if block_type != FOOTER_BLOCK_TYPE:
        return None
    if total_len != FOOTER_BLOCK_SIZE:
        return None
    tail_len = struct.unpack_from("<I", footer_bytes, FOOTER_BLOCK_SIZE - 4)[0]
    if tail_len != total_len:
        return None
    enterprise, magic, version, _reserved, parquet_offset, parquet_len = struct.unpack_from("<I8sHHQQ", footer_bytes, 8)
    if enterprise != ENTERPRISE_ID:
        return None
    if magic != FOOTER_MAGIC:
        return None
    if version > FOOTER_VERSION:
        return None
    return parquet_offset, parquet_len


def _scan_metadata_bytes(data: bytes) -> bytes | None:
    n = len(data)
    i = 0

    while i + 12 <= n:
        block_type = struct.unpack_from("<I", data, i)[0]
        total_len = struct.unpack_from("<I", data, i + 4)[0]
        if total_len < 12 or i + total_len > n:
            break
        tail_len = struct.unpack_from("<I", data, i + total_len - 4)[0]
        if tail_len != total_len:
            break

        if block_type == CUSTOM_BLOCK_TYPE:
            body = data[i + 8 : i + total_len - 4]
            if len(body) >= 4 + 9 + 2 + 2 + 8:
                enterprise = struct.unpack_from("<I", body, 0)[0]
                magic = body[4:13]
                if enterprise == ENTERPRISE_ID and magic == MAGIC:
                    parquet_len = struct.unpack_from("<Q", body, 17)[0]
                    start = 25
                    end = start + parquet_len
                    if end <= len(body):
                        return body[start:end]
        i += total_len
    return None


def extract_metadata_bytes(pqcap_path: Path) -> bytes | None:
    with pqcap_path.open("rb") as f:
        f.seek(0, 2)
        size = f.tell()
        if size >= FOOTER_BLOCK_SIZE:
            f.seek(size - FOOTER_BLOCK_SIZE)
            footer = f.read(FOOTER_BLOCK_SIZE)
            parsed = parse_footer(footer)
            if parsed is not None:
                parquet_offset, parquet_len = parsed
                if parquet_len > 0 and parquet_offset + parquet_len <= size:
                    f.seek(parquet_offset)
                    return f.read(parquet_len)
        # Backward-compatible fallback for pre-footer files.
        f.seek(0)
        data = f.read()
    return _scan_metadata_bytes(data)


def extract_metadata_block(pqcap_path: Path, parquet_out: Path) -> bool:
    metadata = extract_metadata_bytes(pqcap_path)
    if metadata is None:
        return False
    parquet_out.write_bytes(metadata)
    return True


def usage() -> int:
    print("Usage:")
    print("  pqcap_embedded_metadata.py append <capture.pcapng> <metadata.parquet> <output.pqcapng>")
    print("  pqcap_embedded_metadata.py extract <input.pqcapng> <output.parquet>")
    return 1


def main() -> int:
    if len(sys.argv) < 2:
        return usage()
    cmd = sys.argv[1]
    if cmd == "append" and len(sys.argv) == 5:
        append_metadata_block(Path(sys.argv[2]), Path(sys.argv[3]), Path(sys.argv[4]))
        return 0
    if cmd == "extract" and len(sys.argv) == 4:
        ok = extract_metadata_block(Path(sys.argv[2]), Path(sys.argv[3]))
        if not ok:
            print("FAIL: embedded pqcap metadata block not found")
            return 2
        return 0
    return usage()


if __name__ == "__main__":
    raise SystemExit(main())
