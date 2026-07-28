#!/usr/bin/env python3
"""Build a modern PNG-backed ICNS container from a standard iconset."""

from __future__ import annotations

import struct
import sys
from pathlib import Path


CHUNKS = (
    (b"icp4", "icon_16x16.png"),
    (b"icp5", "icon_32x32.png"),
    (b"icp6", "icon_32x32@2x.png"),
    (b"ic07", "icon_128x128.png"),
    (b"ic08", "icon_256x256.png"),
    (b"ic09", "icon_512x512.png"),
    (b"ic10", "icon_512x512@2x.png"),
)


def build(iconset: Path, output: Path) -> None:
    payload = bytearray()
    for chunk_type, name in CHUNKS:
        data = (iconset / name).read_bytes()
        payload.extend(chunk_type)
        payload.extend(struct.pack(">I", len(data) + 8))
        payload.extend(data)

    container = b"icns" + struct.pack(">I", len(payload) + 8) + payload
    output.write_bytes(container)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: build_icns.py ICONSET_DIR OUTPUT.icns")
    build(Path(sys.argv[1]), Path(sys.argv[2]))
