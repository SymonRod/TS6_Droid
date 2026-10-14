"""Generates SYNTHETIC `requestServerItems` replies for the Flutter import tests.

Everything here is disposable test data: the account key is bytes 0..31, the
identity scalars come from identity_vectors.py (public, never used for login),
and every host/name/password is a fabricated placeholder. No account file,
capture or network is read. Output is a Dart source file:

    captures/myts/.venv/bin/python tools/myts/pull_fixture.py \
        > flutter/test/fixtures/synthetic_pull.dart

The item framing mirrors item.py (`IV16 || AES-256-CTR-LE || SHA512`); the
protobuf writer is deliberately independent of the Rust codec.
"""

import base64
import hashlib

from Crypto.Cipher import AES
from Crypto.Util import Counter

import identity_vectors

ACCOUNT_KEY = bytes(range(32))
WRAPPED_KEY_HEX = ("02323ec445370cb098574647e56416e082"
                   "000102030405060708090a0b"
                   "df3d396ab4b8ccefbfd431d67420448f56791f8f13c313943db655c533aaf63b")
EMAIL = "Alice@EXAMPLE.COM"
PASSWORD = "correct horse battery staple"


def varint(value):
    out = bytearray()
    while value >= 0x80:
        out.append((value & 0x7F) | 0x80)
        value >>= 7
    out.append(value)
    return bytes(out)


def field_bytes(number, data):
    return varint(number << 3 | 2) + varint(len(data)) + data


def field_string(number, text):
    return field_bytes(number, text.encode())


def field_uint(number, value):
    return varint(number << 3) + varint(value)


def seal(plain, iv_seed):
    iv = bytes((iv_seed + i) % 256 for i in range(16))
    counter = Counter.new(128, initial_value=int.from_bytes(iv, "little"), little_endian=True)
    cipher = AES.new(ACCOUNT_KEY, AES.MODE_CTR, counter=counter).encrypt(plain)
    return iv + cipher + hashlib.sha512(plain).digest()


def item_plain(uuid, content_field, content, sync_version="synthetic-sync"):
    return (field_string(2, uuid) + field_string(3, sync_version) + field_uint(4, 3)
            + field_bytes(content_field, content))


def detail(uuid, blob, version="outer-1"):
    return field_string(1, uuid) + field_string(2, version) + field_bytes(3, blob)


def identity_content(material, name, nickname, default):
    out = b""
    if material is not None:
        out += field_string(1, material)
    out += field_string(2, name) + field_string(3, nickname)
    if default is not None:
        out += field_uint(5, int(default))
    return out


def bookmark_content(name, address, port, nickname, identity, password, channel=None):
    out = field_string(1, name)
    if address is not None:
        out += field_string(2, address)
    if port is not None:
        out += field_uint(3, port)
    out += field_string(4, nickname)
    if identity is not None:  # present-but-empty is written; absent is omitted
        out += field_bytes(6, identity.encode())
    if password is not None:
        out += field_string(7, password)
    if channel is not None:
        out += field_string(8, channel)
    return out


def klass(number, details):
    out = field_uint(1, number) + field_string(2, "class-v1")
    for d in details:
        out += field_bytes(3, d)
    return out


def reply(classes, status=301):
    out = field_uint(1, status)
    for c in classes:
        out += field_bytes(2, c)
    return out + field_string(3, "global-v1")


def identity_item(uuid, material, name, nickname, default, seed):
    return detail(uuid, seal(item_plain(uuid, 17, identity_content(material, name, nickname, default)), seed))


def bookmark_item(uuid, seed, **kw):
    return detail(uuid, seal(item_plain(uuid, 16, bookmark_content(**kw)), seed))


def build():
    one, pattern, _ = identity_vectors.vectors()
    a = identity_item("cloud-identity-a", one["desktop"], "Identity A", "Alice", True, 1)
    b = identity_item("cloud-identity-b", pattern["desktop"], "Identity B", "Bob", True, 2)
    b1 = bookmark_item("cloud-bookmark-1", 3, name="Server One", address="one.example.invalid",
                       port=9987, nickname="Alice", identity="", password="synthetic-pw-1",
                       channel="Lobby")
    b2 = bookmark_item("cloud-bookmark-2", 4, name="Server Two", address="two.example.invalid",
                       port=9988, nickname="", identity=None, password=None)
    b3 = bookmark_item("cloud-bookmark-3", 5, name="Server Three", address="three.example.invalid",
                       port=None, nickname="Carol", identity="cloud-identity-b", password=None)
    replies = {
        "full": reply([klass(0, [b1, b2, b3]), klass(1, [a, b])]),
        "empty": reply([klass(0, []), klass(1, [])]),
    }
    bad_identity = identity_item("cloud-identity-bad", "synthetic-not-an-identity", "Bad", "Bad", None, 6)
    no_address = bookmark_item("cloud-bookmark-noaddr", 7, name="No address", address=None,
                               port=9987, nickname="X", identity="", password=None)
    replies["partly_invalid"] = reply([klass(0, [b1, no_address]), klass(1, [a, bad_identity])])
    # Same key as identity A under another cloud ID (duplicate UID).
    a_dup = identity_item("cloud-identity-a-copy", one["desktop"], "Identity A copy", "Alice", None, 8)
    replies["duplicate_uid"] = reply([klass(0, [b1]), klass(1, [a, a_dup])])
    # Same cloud ID as bookmark 1 but different content (kept, not replaced).
    b1_changed = bookmark_item("cloud-bookmark-1", 9, name="Server One renamed",
                               address="one.example.invalid", port=9987, nickname="Alice2",
                               identity="", password="synthetic-pw-changed")
    replies["changed"] = reply([klass(0, [b1_changed]), klass(1, [a])])
    # One flipped bit inside an item: the integrity check must fail the batch.
    raw = bytearray(replies["full"])
    raw[len(raw) // 2] ^= 0x01
    replies["tampered"] = bytes(raw)
    return replies


def dart_literal(name, data):
    return "final %s = base64Decode(\n    '%s');\n" % (name, base64.b64encode(data).decode())


def main():
    one, pattern, _ = identity_vectors.vectors()
    print("// GENERATED by tools/myts/pull_fixture.py - synthetic data only; do not edit.")
    print("// ignore_for_file: lines_longer_than_80_chars")
    print("import 'dart:convert';\n")
    print("const fixtureEmail = %r;" % EMAIL)
    print("const fixturePassword = %r;" % PASSWORD)
    print("final fixtureWrappedKey = base64Decode(\n    '%s');" % base64.b64encode(bytes.fromhex(WRAPPED_KEY_HEX)).decode())
    print("const fixtureUidA = %r;" % one["uid"])
    print("const fixtureUidB = %r;" % pattern["uid"])
    print("final fixtureCounterB = BigInt.parse('%d');" % pattern["counter"])
    print("const fixtureDesktopA = %r;" % one["desktop"])
    print("const fixtureDesktopB = %r;\n" % pattern["desktop"])
    for key, data in build().items():
        print(dart_literal("fixturePull" + "".join(p.capitalize() for p in key.split("_")), data))


if __name__ == "__main__":
    main()
