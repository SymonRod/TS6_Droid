"""Offline reference for the demonstrated run41b sync-item provider.

Not the account-key GCM envelope: IV16 || AES256-CTR-LE(P) || SHA512(P).
The unkeyed digest checks integrity, NOT cryptographic authenticity. This is
research code; application crypto belongs in tslib-myts, not Python or Dart.
"""

import hashlib
import hmac

from Crypto.Cipher import AES
from Crypto.Util import Counter


class ItemError(ValueError):
    """Invalid framing/key or a failed plaintext digest check (no secret data)."""


def decrypt_item(blob: bytes, account_key: bytes) -> bytes:
    """Return plaintext only after checking the trailing SHA-512 digest.

    Supports only the observed unversioned provider. Do not auto-detect other
    formats, strip an account version byte, or accept plaintext on failure.
    """
    if len(account_key) != 32:
        raise ItemError("account key must be 32 bytes")
    if len(blob) <= 80:
        raise ItemError("item must contain IV16, nonempty ciphertext and SHA512")
    counter = Counter.new(128, initial_value=int.from_bytes(blob[:16], "little"),
                          little_endian=True)
    plain = AES.new(account_key, AES.MODE_CTR, counter=counter).decrypt(blob[16:-64])
    if not hmac.compare_digest(hashlib.sha512(plain).digest(), blob[-64:]):
        raise ItemError("item integrity check failed")
    return plain
