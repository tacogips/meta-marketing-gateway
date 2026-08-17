#!/usr/bin/env python3
"""Replace Mach-O LC_UUID payloads with zeros for reproducible local archives."""

import pathlib
import struct
import sys

LC_UUID = 0x1B
MH_MAGIC_64 = 0xFEEDFACF

for raw_path in sys.argv[1:]:
    path = pathlib.Path(raw_path)
    data = bytearray(path.read_bytes())
    if len(data) < 32 or struct.unpack_from("<I", data)[0] != MH_MAGIC_64:
        raise SystemExit(f"not a thin 64-bit Mach-O: {path}")
    command_count = struct.unpack_from("<I", data, 16)[0]
    offset = 32
    for _ in range(command_count):
        command, size = struct.unpack_from("<II", data, offset)
        if size < 8 or offset + size > len(data):
            raise SystemExit(f"malformed load command: {path}")
        if command == LC_UUID:
            if size != 24:
                raise SystemExit(f"unexpected LC_UUID size: {path}")
            data[offset + 8 : offset + 24] = b"\0" * 16
        offset += size
    path.write_bytes(data)
