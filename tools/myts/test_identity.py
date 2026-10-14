"""Synthetic identity encoding reference; does not access the desktop profile."""

import base64
import hashlib
import unittest

from identity_vectors import OBFUSCATION, tomcrypt, vectors


class IdentityTests(unittest.TestCase):
    def test_p256_generator_public_uid(self):
        # SEC2 P-256 generator (private scalar 1); independent known coordinates.
        public = tomcrypt(1, False)
        self.assertIn(bytes.fromhex("6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296"), public)
        self.assertIn(bytes.fromhex("4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5"), public)
        self.assertEqual("6Gj4WmRDl6pf8IWg27Gh0E2Wq2Q=", vectors()[0]["uid"])

    def test_obfuscation_inverse(self):
        goldens = [
            ("6Gj4WmRDl6pf8IWg27Gh0E2Wq2Q=", "85f751df52926fd12e258d8c0f5be47d08a677a0"),
            ("gM4pUv4ozDqs1Z22u18ifJO/9Po=", "ad0fdccaea73b06650176feed28c5b5e83d47baf"),
            ("tiVSHDb2KeglykG74AxUj03v1ZQ=", "17bc693fdcfd2c0541b15998cd10a8348dc7fc8f"),
        ]
        for item, (uid, obfuscated_hash) in zip(vectors(), goldens):
            with self.subTest(name=item["name"]):
                obfuscated = item["desktop"].split("V", 1)[1]
                self.assertEqual(uid, item["uid"])
                self.assertEqual(obfuscated_hash, hashlib.sha1(obfuscated.encode()).hexdigest())
                data = bytearray(base64.b64decode(obfuscated))
                digest = hashlib.sha1(bytes(data[20:]).split(b"\x00", 1)[0]).digest()
                for index in range(20):
                    data[index] ^= digest[index]
                for index in range(min(100, len(data))):
                    data[index] ^= OBFUSCATION[index]
                self.assertEqual(item["raw"].encode(), data)

    def test_uid_hashes_base64_public_der_not_der_or_private_or_counter(self):
        for item in vectors():
            expected = base64.b64decode(item["uid"])
            self.assertEqual(expected, hashlib.sha1(item["public"].encode()).digest())
            for wrong in (base64.b64decode(item["public"]), item["raw"].encode(), item["desktop"].encode()):
                self.assertNotEqual(expected, hashlib.sha1(wrong).digest())


if __name__ == "__main__":
    unittest.main()
