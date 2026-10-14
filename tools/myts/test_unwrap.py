"""Synthetic account-key goldens and fail-closed tests; no network or account."""

import unittest

from Crypto.Cipher import AES

from unwrap import AccountKeyError, encryption_password, unwrap_account_key


# Fabricated credentials/key/nonce; safe to commit. See the run41 reference.
EMAIL = "Alice@EXAMPLE.COM"
PASSWORD = "correct horse battery staple"
ENCRYPTION_VALUE = bytes.fromhex(
    "92e837501d0748edbbd279e32f49931626851ca6d97b5658e3c522c533654e45"
)
ACCOUNT_KEY = bytes(range(32))
WRAPPED_KEY = bytes.fromhex(
    "02323ec445370cb098574647e56416e082"
    "000102030405060708090a0b"
    "df3d396ab4b8ccefbfd431d67420448f56791f8f13c313943db655c533aaf63b"
)


class UnwrapTests(unittest.TestCase):
    def test_encryption_derivation_golden_and_email_case(self):
        for email in (EMAIL, EMAIL.lower()):
            self.assertEqual(ENCRYPTION_VALUE, encryption_password(email, PASSWORD))

    def test_password_whitespace_and_case_are_significant(self):
        for password in (" " + PASSWORD, PASSWORD + " ", PASSWORD.upper()):
            self.assertNotEqual(ENCRYPTION_VALUE, encryption_password(EMAIL, password))

    def test_synthetic_envelope_golden(self):
        self.assertEqual(ACCOUNT_KEY, unwrap_account_key(WRAPPED_KEY, ENCRYPTION_VALUE))

    def test_exact_field_order_round_trip(self):
        cipher = AES.new(ENCRYPTION_VALUE, AES.MODE_GCM,
                         nonce=bytes(range(12)), mac_len=16)
        ciphertext, tag = cipher.encrypt_and_digest(ACCOUNT_KEY)
        self.assertEqual(WRAPPED_KEY, b"\x02" + tag + bytes(range(12)) + ciphertext)

    def test_nist_zero_key_aes256_gcm_vector(self):
        # Published AES-256-GCM zero-key/zero-IV, one-block, empty-AAD vector.
        ciphertext = bytes.fromhex("cea7403d4d606b6e074ec5d3baf39d18")
        tag = bytes.fromhex("d0d1c8a799996bf0265b98b5d48ab919")
        cipher = AES.new(bytes(32), AES.MODE_GCM, nonce=bytes(12), mac_len=16)
        self.assertEqual(bytes(16), cipher.decrypt_and_verify(ciphertext, tag))

    def test_wrong_password_fails_authentication(self):
        wrong = encryption_password(EMAIL, "wrong synthetic password")
        with self.assertRaisesRegex(AccountKeyError, "authentication failed"):
            unwrap_account_key(WRAPPED_KEY, wrong)

    def test_every_authenticated_byte_rejects_tampering(self):
        for index in range(1, len(WRAPPED_KEY)):
            with self.subTest(index=index):
                damaged = bytearray(WRAPPED_KEY)
                damaged[index] ^= 1
                with self.assertRaisesRegex(AccountKeyError, "authentication failed"):
                    unwrap_account_key(bytes(damaged), ENCRYPTION_VALUE)

    def test_unsupported_versions(self):
        for version in (0, 1, 3, 255):
            with self.subTest(version=version):
                with self.assertRaisesRegex(AccountKeyError, "unsupported.*version"):
                    unwrap_account_key(bytes([version]) + WRAPPED_KEY[1:], ENCRYPTION_VALUE)

    def test_truncated_or_extended_envelopes(self):
        for length in range(len(WRAPPED_KEY)):
            with self.subTest(length=length):
                with self.assertRaises(AccountKeyError):
                    unwrap_account_key(WRAPPED_KEY[:length], ENCRYPTION_VALUE)
        with self.assertRaises(AccountKeyError):
            unwrap_account_key(WRAPPED_KEY + b"\x00", ENCRYPTION_VALUE)

    def test_wrong_encryption_value_sizes(self):
        for length in (0, 16, 31, 33, 64):
            with self.subTest(length=length):
                with self.assertRaisesRegex(AccountKeyError, "must be 32 bytes"):
                    unwrap_account_key(WRAPPED_KEY, bytes(length))


if __name__ == "__main__":
    unittest.main()
