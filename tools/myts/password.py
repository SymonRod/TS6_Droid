"""Offline myTeamSpeak login derivation demonstrated in run40 (no network)."""

import base64
import hashlib


def login_password(email: str, password: str) -> str:
    # Desktop uses byte-wise std::ctype<char>::tolower, not Unicode case folding.
    email_bytes = email.encode("utf-8").lower()
    password_bytes = password.encode("utf-8")
    salt = email_bytes + b"ts3Login" + password_bytes
    derived = hashlib.pbkdf2_hmac("sha512", password_bytes, salt, 10_000, 48)
    return base64.b64encode(derived).decode("ascii")
