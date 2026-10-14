#!/usr/bin/env python3
"""Recheck the run41 account unwrap offline; print only metadata/booleans.

No network calls. Real captures and .env are private inputs, never fixtures.
The capture filenames below describe the successful run41b observation order.
Requires that build's recovered descriptors and the isolated research venv.
"""

import argparse
import hmac
from pathlib import Path

from dotenv import dotenv_values

from standalone_login import classes
from unwrap import AccountKeyError, encryption_password, unwrap_account_key


def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify(capture, descriptors, credentials):
    def read(name):
        return (capture / name).read_bytes()

    reply = classes(descriptors)["LoginSession"].FromString(read("002-http-login-reply.bin"))
    require(reply.error == 200 and bool(reply.session), "not a successful login capture")
    derived = read("001-derive-encryption-result0.bin")
    native_key = read("003-split-authenticated-blob-rcx.bin")
    native_blob = read("003-split-authenticated-blob-rdx.bin")
    native_plain = read("003-split-authenticated-blob-result0.bin")
    require(hmac.compare_digest(reply.key[1:], native_blob), "server/native envelope mismatch")
    require(hmac.compare_digest(derived, native_key), "native encryption-value mismatch")
    require(hmac.compare_digest(native_key, read("004-authenticated-core-rdx.bin")),
            "authenticated-core key mismatch")
    require(hmac.compare_digest(native_blob,
            read("004-authenticated-core-result1.bin") +
            read("004-authenticated-core-rcx.bin") +
            read("004-authenticated-core-r8.bin")), "tag/nonce/ciphertext layout mismatch")
    opened = unwrap_account_key(reply.key, derived)
    require(hmac.compare_digest(opened, native_plain), "offline/native plaintext mismatch")
    require(hmac.compare_digest(opened, read("004-authenticated-core-result0.bin")),
            "native high-level/core plaintext mismatch")
    if credentials is not None:
        values = dotenv_values(credentials)
        email = values.get("EMAIL") or values.get("USERNAME")
        require(bool(email) and bool(values.get("PASSWORD")), "credential fields missing")
        require(hmac.compare_digest(derived, encryption_password(email, values["PASSWORD"])),
                "password derivation/native mismatch")
    damaged = bytearray(reply.key)
    damaged[-1] ^= 1
    try:
        unwrap_account_key(bytes(damaged), derived)
    except AccountKeyError:
        pass
    else:
        raise ValueError("altered envelope was accepted")
    print("login_error=200 wrapped_key_bytes=%d version=%d opened_key_bytes=%d" %
          (len(reply.key), reply.key[0], len(opened)))
    print("server/native correlation, AES-GCM authentication and plaintext equality: OK")
    print("altered ciphertext rejected: OK")
    if credentials is not None:
        print("password derivation/native equality: OK")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture", required=True, type=Path)
    parser.add_argument("--descriptors", required=True, type=Path)
    parser.add_argument("--env", type=Path, help="optional offline KDF comparison")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    require(args.capture.resolve().is_relative_to(root / "captures"), "unsafe capture directory")
    require(args.descriptors.resolve().is_relative_to(root / "captures"), "unsafe descriptor directory")
    try:
        verify(args.capture, args.descriptors, args.env)
    except Exception as error:
        # Parser/library exceptions can include input bytes; suppress all details.
        print("offline verification failed (%s); secret details suppressed" % type(error).__name__)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
