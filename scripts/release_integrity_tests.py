#!/usr/bin/env python3
"""Synthetic PNG/settings regressions; never product or submission evidence."""
import json
from pathlib import Path
import struct
import tempfile
import unittest
import zlib
from release_png import png_size
from release_settings import validate
from release_preflight_tests import png


def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))


class PNGTests(unittest.TestCase):
    def size(self, data):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'test.png'; path.write_bytes(data)
            return png_size(path)

    def test_valid_complete_png(self):
        self.assertEqual(self.size(png(32, 64)), (32, 64))

    def test_missing_truncated_and_trailing_chunks(self):
        valid = png(32, 64)
        for data in (b'', valid[:24], valid[:-12], valid[:-1], valid + b'x'):
            with self.subTest(size=len(data)): self.assertIsNone(self.size(data))

    def test_crc_and_duplicate_header(self):
        valid = png(32, 64)
        self.assertIsNone(self.size(valid[:29] + b'xxxx' + valid[33:]))
        self.assertIsNone(self.size(valid[:33] + valid[8:33] + valid[33:]))

    def test_incorrect_compressed_data_length_and_filters(self):
        head = png(1, 1)[:33]
        for raw in (b'', b'\0\xff', b'\0\xff\xff\xff\0', b'\5\xff\xff\xff'):
            self.assertIsNone(self.size(head + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')))

    def test_corrupt_compression_unknown_critical_and_animation(self):
        valid = png(1, 1)
        self.assertIsNone(self.size(valid[:33] + chunk(b'IDAT', b'not-zlib') + chunk(b'IEND', b'')))
        for name in (b'FAKE', b'acTL'):
            self.assertIsNone(self.size(valid[:33] + chunk(name, b'') + valid[33:]))

    def test_pixel_and_decompression_limits(self):
        head = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 100000, 100000, 8, 2, 0, 0, 0))
        self.assertIsNone(self.size(head + chunk(b'IDAT', zlib.compress(b'x')) + chunk(b'IEND', b'')))
        head = png(1, 1)[:33]
        self.assertIsNone(self.size(head + chunk(b'IDAT', zlib.compress(b'\0' * 100000)) + chunk(b'IEND', b'')))

    def test_adam7_one_pixel_and_ancillary_chunks(self):
        head = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 1))
        data = head + chunk(b'tEXt', b'Note\0Synthetic') + chunk(b'IDAT', zlib.compress(b'\0\xff\xff\xff')) + chunk(b'IEND', b'')
        self.assertEqual(self.size(data), (1, 1))


class SettingsTests(unittest.TestCase):
    def setUp(self):
        self.config = json.loads((Path(__file__).resolve().parents[1] / 'appstore/release_config.json').read_text())

    def test_current_candidate_valid_but_not_approved(self):
        self.assertEqual(validate(self.config), [])
        self.assertFalse(self.config['release_ready'])

    def test_rejects_injection_missing_and_wrong_types(self):
        for field in ('build_number', 'candidate_bundle_id', 'candidate_app_group_id', 'marketing_version', 'minimum_runtime_ios'):
            for value in (None, 1, '', 'bad\nKEY = value', '$(SHELL)'):
                with self.subTest(field=field, value=value):
                    self.assertTrue(validate(dict(self.config, **{field: value})))

    def test_name_limits(self):
        for name in ('', 'x' * 31, 'a\nb'):
            self.assertTrue(validate(dict(self.config, candidate_name=name)))


if __name__ == '__main__': unittest.main()
