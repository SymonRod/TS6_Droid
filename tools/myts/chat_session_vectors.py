"""Synthetic cloud-chat envelopes; never load account data or captures.

Research only. The native desktop oracle independently checks these envelopes.
Production protocol/crypto belongs in tslib-myts.
"""

import base64
import hashlib
import json

from Crypto.Cipher import AES
from Crypto.Util import Counter

from item import decrypt_item


ACCOUNT_KEY = bytes(range(32))  # Public, deliberately unsafe synthetic key.


def plaintext():
    # The key strings are placeholders, NOT valid Megolm/Ed25519 material.
    return json.dumps({
        "version": "1",
        "room_id": "!synthetic:example.invalid",
        "group_session_id": "synthetic-session",
        "algorithm": "m.megolm.v1.aes-sha2",
        "type": 3,
        "group_session_key": "synthetic-not-a-megolm-key",
        "chain_index": 0,
        "sender": "@synthetic:example.invalid",
        "c25519": "synthetic-curve-key",
        "ed25519": "synthetic-signing-key",
    }, sort_keys=True, separators=(",", ":")).encode()


def wrap(plain, key=ACCOUNT_KEY, iv=bytes(range(16))):
    counter = Counter.new(128, initial_value=int.from_bytes(iv, "little"),
                          little_endian=True)
    encrypted = AES.new(key, AES.MODE_CTR, counter=counter).encrypt(plain)
    return base64.b64encode(iv + encrypted + hashlib.sha512(plain).digest())


def unwrap(encoded, key=ACCOUNT_KEY):
    return decrypt_item(base64.b64decode(encoded, validate=True), key)


def vectors():
    return [
        {"name": "session-json", "plain": plaintext()},
        {"name": "short", "plain": b"x"},
        {"name": "multi-block", "plain": bytes(range(256)) + b"partial"},
    ]
