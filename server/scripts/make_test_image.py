"""Emit a small PNG as a data URL — a four-colour quadrant, 64x64.

Used to check that image input survives the whole path: agent -> server ->
WebSocket -> human console. Writes the data URL to stdout so it can be
sent straight to the API without a temporary file.
"""
import base64
import struct
import sys
import zlib


def chunk(tag: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def build_png(size: int = 64) -> bytes:
    # Quadrants: red, green, blue, yellow (clockwise from top-left).
    quadrants = [
        ((0, 0), (255, 60, 60)),
        ((1, 0), (80, 220, 120)),
        ((0, 1), (90, 140, 255)),
        ((1, 1), (250, 200, 70)),
    ]
    half = size // 2

    rows = bytearray()
    for y in range(size):
        rows.append(0)  # filter type 0
        for x in range(size):
            qx, qy = (0, 0) if x < half else (1, 0)
            if y >= half:
                qx, qy = (0, 1) if x < half else (1, 1)
            colour = next(c for (pos, c) in quadrants if pos == (qx, qy))
            rows.extend(colour)

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(rows), 9))
        + chunk(b"IEND", b"")
    )


if __name__ == "__main__":
    png = build_png(int(sys.argv[1]) if len(sys.argv) > 1 else 64)
    print("data:image/png;base64," + base64.b64encode(png).decode())
