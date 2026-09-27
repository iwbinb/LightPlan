"""Bounded PNG integrity validation for native screenshot packaging.

Checks chunk CRC/order and the complete decompressed scanline stream, including
Adam7 passes. Does not certify visual content, provenance or color appearance.
"""
from __future__ import annotations
from pathlib import Path
import struct
import zlib

MAX_FILE = 64 * 1024 * 1024
MAX_PIXELS = 16_000_000
MAX_RAW = 128 * 1024 * 1024


def png_size(path: Path) -> tuple[int, int] | None:
    try:
        if not 45 <= path.stat().st_size <= MAX_FILE:
            return None
        with path.open("rb") as stream:
            data = stream.read(MAX_FILE + 1)
        if len(data) > MAX_FILE or data[:8] != b"\x89PNG\r\n\x1a\n":
            return None
        offset, ihdr, palette, started, ended = 8, None, False, False, False
        compressed = bytearray()
        while offset < len(data):
            if offset + 12 > len(data):
                return None
            size = struct.unpack_from(">I", data, offset)[0]
            kind = data[offset + 4:offset + 8]
            stop = offset + 12 + size
            if stop > len(data) or len(kind) != 4 or not all(65 <= c <= 90 or 97 <= c <= 122 for c in kind):
                return None
            body = data[offset + 8:offset + 8 + size]
            crc = struct.unpack_from(">I", data, offset + 8 + size)[0]
            if zlib.crc32(kind + body) != crc or (ihdr is None and kind != b"IHDR"):
                return None
            if kind == b"IHDR":
                if ihdr is not None or size != 13:
                    return None
                ihdr = struct.unpack(">IIBBBBB", body)
                width, height, depth, color, compression, filtering, interlace = ihdr
                allowed = {0: (1, 2, 4, 8, 16), 2: (8, 16), 3: (1, 2, 4, 8), 4: (8, 16), 6: (8, 16)}
                if (not width or not height or width * height > MAX_PIXELS or depth not in allowed.get(color, ())
                        or compression != 0 or filtering != 0 or interlace not in (0, 1)):
                    return None
            elif kind == b"PLTE":
                if palette or started or size == 0 or size % 3 or size > 768 or color in (0, 4):
                    return None
                palette = True
            elif kind == b"IDAT":
                if ended or (color == 3 and not palette):
                    return None
                started = True
                compressed.extend(body)
            elif kind == b"IEND":
                if size or stop != len(data) or not started:
                    return None
                break
            elif kind == b"acTL" or not kind[0] & 32:
                return None  # Animated images and unknown critical chunks are not screenshots.
            elif started:
                ended = True
            offset = stop
        else:
            return None  # IEND is mandatory.
        channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color]
        passes = [(0, 0, 1, 1)] if interlace == 0 else [
            (0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4),
            (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2)]
        rows = []
        for x, y, dx, dy in passes:
            w, h = max(0, (width - x + dx - 1) // dx), max(0, (height - y + dy - 1) // dy)
            if w and h:
                rows.append(((w * channels * depth + 7) // 8 + 1, h))
        expected = sum(n * count for n, count in rows)
        if expected > MAX_RAW:
            return None
        decoder = zlib.decompressobj()
        raw = decoder.decompress(compressed, expected + 1)
        if len(raw) != expected or not decoder.eof or decoder.unconsumed_tail or decoder.unused_data:
            return None
        position = 0
        for size, count in rows:
            for _ in range(count):
                if raw[position] > 4:
                    return None
                position += size
        return width, height
    except (OSError, ValueError, struct.error, zlib.error, OverflowError):
        return None
