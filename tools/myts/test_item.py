"""Synthetic sync-item vectors and limits; no account or network required."""

import hashlib
import unittest

from Crypto.Cipher import AES
from Crypto.Util import Counter

from item import ItemError, decrypt_item
from item_vectors import ACCOUNT_KEY, BOOKMARK_BLOB, BOOKMARK_PLAIN, CARRY_BLOB
from test_unwrap import ENCRYPTION_VALUE, WRAPPED_KEY
from unwrap import unwrap_account_key


def seal(plain, iv=bytes(range(16))):
    counter = Counter.new(128, initial_value=int.from_bytes(iv, "little"), little_endian=True)
    return iv + AES.new(ACCOUNT_KEY, AES.MODE_CTR, counter=counter).encrypt(plain) + hashlib.sha512(plain).digest()


class ItemTests(unittest.TestCase):
    def test_published_aes256_block_vector(self):
        # FIPS 197 AES-256: CTR's first keystream block is AES(key, IV).
        iv = bytes.fromhex("00112233445566778899aabbccddeeff")
        ciphertext = bytes.fromhex("8ea2b7ca516745bfeafc49904b496089")
        blob = iv + ciphertext + hashlib.sha512(bytes(16)).digest()
        self.assertEqual(bytes(16), decrypt_item(blob, ACCOUNT_KEY))

    def test_synthetic_bookmark_golden(self):
        self.assertEqual(BOOKMARK_PLAIN, decrypt_item(BOOKMARK_BLOB, ACCOUNT_KEY))
        self.assertEqual(BOOKMARK_BLOB, seal(BOOKMARK_PLAIN))

    def test_account_unwrap_to_bookmark(self):
        account = unwrap_account_key(WRAPPED_KEY, ENCRYPTION_VALUE)
        self.assertEqual(BOOKMARK_PLAIN, decrypt_item(BOOKMARK_BLOB, account))

    def test_little_endian_full_width_carry_and_partial_block(self):
        self.assertEqual(bytes(range(49)), decrypt_item(CARRY_BLOB, ACCOUNT_KEY))
        self.assertEqual(CARRY_BLOB, seal(bytes(range(49)), CARRY_BLOB[:16]))

    def test_block_lengths(self):
        for length in (1, 15, 16, 17, 31, 32, 33, 255):
            with self.subTest(length=length):
                plain = bytes(range(length))
                self.assertEqual(plain, decrypt_item(seal(plain), ACCOUNT_KEY))

    def test_wrong_key_and_wrong_key_lengths(self):
        for key in (bytes(32), ENCRYPTION_VALUE, bytes(0), bytes(16), bytes(31), bytes(33), bytes(64)):
            with self.assertRaises(ItemError):
                decrypt_item(BOOKMARK_BLOB, key)

    def test_every_byte_rejects_single_byte_tampering(self):
        for index in range(len(BOOKMARK_BLOB)):
            with self.subTest(index=index):
                damaged = bytearray(BOOKMARK_BLOB)
                damaged[index] ^= 1
                with self.assertRaises(ItemError):
                    decrypt_item(bytes(damaged), ACCOUNT_KEY)

    def test_truncated_extended_and_empty(self):
        for length in range(len(BOOKMARK_BLOB)):
            with self.subTest(length=length):
                with self.assertRaises(ItemError):
                    decrypt_item(BOOKMARK_BLOB[:length], ACCOUNT_KEY)
        for blob in (BOOKMARK_BLOB + b"\x00", seal(b"")):
            with self.assertRaises(ItemError):
                decrypt_item(blob, ACCOUNT_KEY)

    def test_no_account_version_header(self):
        with self.assertRaises(ItemError):
            decrypt_item(b"\x02" + BOOKMARK_BLOB, ACCOUNT_KEY)

    def test_plaintext_digest_not_ciphertext_digest(self):
        blob = BOOKMARK_BLOB[:-64] + hashlib.sha512(BOOKMARK_BLOB[16:-64]).digest()
        with self.assertRaises(ItemError):
            decrypt_item(blob, ACCOUNT_KEY)

    def test_unkeyed_digest_is_not_authentication(self):
        # An attacker knowing P can choose same-length P' without the key:
        # C' = C XOR P XOR P', and replace the exposed digest with SHA512(P').
        changed = BOOKMARK_PLAIN.replace(b"Lobby", b"Other")
        ciphertext = bytes(c ^ p ^ q for c, p, q in
                           zip(BOOKMARK_BLOB[16:-64], BOOKMARK_PLAIN, changed))
        forged = BOOKMARK_BLOB[:16] + ciphertext + hashlib.sha512(changed).digest()
        self.assertEqual(changed, decrypt_item(forged, ACCOUNT_KEY))


if __name__ == "__main__":
    unittest.main()
