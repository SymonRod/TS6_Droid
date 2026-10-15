"""Synthetic framing checks; desktop compatibility has a separate native oracle."""

import base64
import hashlib
import unittest

from chat_session_vectors import ACCOUNT_KEY, plaintext, unwrap, vectors, wrap
from item import ItemError


class ChatSessionEnvelopeTests(unittest.TestCase):
    def test_synthetic_round_trips(self):
        for vector in vectors():
            with self.subTest(vector["name"]):
                self.assertEqual(unwrap(wrap(vector["plain"])), vector["plain"])

    def test_unversioned_item_framing(self):
        plain = plaintext()
        blob = base64.b64decode(wrap(plain), validate=True)
        self.assertEqual(blob[:16], bytes(range(16)))
        self.assertEqual(len(blob), len(plain) + 80)
        self.assertEqual(blob[-64:], hashlib.sha512(plain).digest())

    def test_digest_and_wrong_key_rejected(self):
        blob = bytearray(base64.b64decode(wrap(plaintext())))
        for position in (0, 16, len(blob) - 1):
            damaged = blob.copy()
            damaged[position] ^= 1
            with self.subTest(position=position), self.assertRaises(ItemError):
                unwrap(base64.b64encode(damaged))
        with self.assertRaises(ItemError):
            unwrap(wrap(plaintext()), bytes(reversed(ACCOUNT_KEY)))

    def test_truncated_and_invalid_base64_rejected(self):
        with self.assertRaises(ItemError):
            unwrap(base64.b64encode(bytes(80)))
        with self.assertRaises(ValueError):
            unwrap(b"not valid base64!")


if __name__ == "__main__":
    unittest.main()
