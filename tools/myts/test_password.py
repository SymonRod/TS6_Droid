"""Synthetic offline goldens, independently reproducible with Python hashlib."""

import unittest

from password import login_password


class PasswordTests(unittest.TestCase):
    def test_short_ascii_vector(self):
        self.assertEqual(
            "jj4pMIxs3fEOw+NaR3mKjAY3hjGWUkBjkdvAzdLVa8X3G1XYWQ8gnz13hTOilOsi",
            login_password("a@b", "pw"),
        )

    def test_ascii_golden_and_email_case(self):
        expected = "rn8XzshqPQxIb7jPVZNLnVQrIpD42wx3qeo6uKVh7naW8LiH0ZEEtgUOA+4TZlIw"
        for email in ("Alice@EXAMPLE.COM", "alice@example.com"):
            self.assertEqual(expected, login_password(email, "correct horse battery staple"))

    def test_utf8_password(self):
        self.assertEqual(
            "DyeSsvb4vLhbiBtn1NU+pj6EoR74H0A+xuNPWBWNo5EPUotPWEPyiCMI7jS93UUC",
            login_password("I@EXAMPLE.COM", "päss🔑"),
        )

    def test_password_whitespace_is_significant(self):
        self.assertEqual(
            "xgFgM9ArJRO+1hxCKGDaavzAmtO/gHwKNJEgCv/18DnWS2M4dWr0XJ3wZDZmlGXA",
            login_password("alice@example.com", " password "),
        )
        self.assertNotEqual(login_password("alice@example.com", "password"),
                            login_password("alice@example.com", " password "))

    def test_empty_password(self):
        self.assertEqual(
            "T5Ir2MZzYi7mdaVfjcMGo+Hbftrj5XZvGChm9YfkT05k4ZzTbWW1rByv8xpa+CKU",
            login_password("a@b", ""),
        )


if __name__ == "__main__":
    unittest.main()
