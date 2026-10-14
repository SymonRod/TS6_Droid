"""Offline account-key unwrap demonstrated against the desktop in run41.

This is a research reference, not a Flutter integration or an item decryptor.
Requires PyCryptodome in the isolated research environment. All inputs and
outputs are secrets; callers must not log or persist them in ordinary storage.
Only the demonstrated version-2 envelope for a 32-byte account key is supported.
"""

import hashlib

from Crypto.Cipher import AES


class AccountKeyError(ValueError):
    """Unsupported, malformed or unauthenticated account key; no secret detail."""


def encryption_password(email: str, password: str) -> bytes:
    # Same demonstrated ASCII byte-lowercase/UTF-8 rule as the login KDF.
    email_bytes = email.encode("utf-8").lower()
    password_bytes = password.encode("utf-8")
    salt = email_bytes + b"ts3Encryption" + password_bytes
    return hashlib.pbkdf2_hmac("sha512", password_bytes, salt, 10_000, 32)


def unwrap_account_key(wrapped_key: bytes, encryption_value: bytes) -> bytes:
    """Authenticate and open LoginSession.key, never return unverified bytes.

    Demonstrated format: 0x02 || tag[16] || nonce[12] || ciphertext[32].
    AES-256-GCM uses the password-derived encryption value, with empty AAD.
    Fail closed for other versions/sizes until those formats are established.
    """
    if len(encryption_value) != 32:
        raise AccountKeyError("encryption value must be 32 bytes")
    if not wrapped_key or wrapped_key[0] != 2:
        raise AccountKeyError("unsupported account-key version")
    if len(wrapped_key) != 61:
        raise AccountKeyError("unsupported account-key length")
    tag, nonce, ciphertext = wrapped_key[1:17], wrapped_key[17:29], wrapped_key[29:]
    cipher = AES.new(encryption_value, AES.MODE_GCM, nonce=nonce, mac_len=16)
    try:
        return cipher.decrypt_and_verify(ciphertext, tag)
    except ValueError:
        raise AccountKeyError("account-key authentication failed") from None
