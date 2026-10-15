"""Offline Megolm fixture helper using only the pinned desktop's libolm.

Research, not application crypto or a TeamSpeak Go JSON-import implementation.
All entropy and message contents are public synthetic data. No profiles, account
data, network calls or dependencies beyond the existing research environment.
"""

import ctypes as c
import hashlib
import json
from pathlib import Path


LIBRARY = Path(__file__).resolve().parents[3] / "teamspeak/libolm.so.3"
EXPECTED_SHA256 = "aeedb3e134c7976f194aa156847a6a6c9889df6983e017c4bbd7f6a40470459c"
ROOM = "!synthetic:example.invalid"
ERROR = c.c_size_t(-1).value


class OlmError(ValueError):
    pass


class Olm:
    def __init__(self):
        if hashlib.sha256(LIBRARY.read_bytes()).hexdigest() != EXPECTED_SHA256:
            raise ValueError("libolm build mismatch")
        self.lib = c.CDLL(str(LIBRARY))
        # Explicit signatures are essential: default ctypes int truncates pointers.
        p, s, u = c.c_void_p, c.c_size_t, c.c_uint32
        for direction in ("inbound", "outbound"):
            stem = "olm_" + direction + "_group_session"
            self.bind(stem + "_size", s, [])
            self.bind(stem, p, [p])
            self.bind(stem + "_last_error", c.c_char_p, [p])
            self.bind("olm_clear_" + direction + "_group_session", s, [p])
            self.bind(stem + "_id_length", s, [p])
            self.bind(stem + "_id", s, [p, p, s])
        self.bind("olm_init_outbound_group_session_random_length", s, [p])
        self.bind("olm_init_outbound_group_session", s, [p, p, s])
        self.bind("olm_outbound_group_session_key_length", s, [p])
        self.bind("olm_outbound_group_session_key", s, [p, p, s])
        self.bind("olm_group_encrypt_message_length", s, [p, s])
        self.bind("olm_group_encrypt", s, [p, p, s, p, s])
        self.bind("olm_init_inbound_group_session", s, [p, p, s])
        self.bind("olm_import_inbound_group_session", s, [p, p, s])
        self.bind("olm_export_inbound_group_session_length", s, [p])
        self.bind("olm_export_inbound_group_session", s, [p, p, s, u])
        self.bind("olm_group_decrypt_max_plaintext_length", s, [p, p, s])
        self.bind("olm_group_decrypt", s, [p, p, s, p, s, c.POINTER(u)])
        self.bind("olm_inbound_group_session_first_known_index", u, [p])
        self.bind("olm_inbound_group_session_is_verified", c.c_int, [p])

    def bind(self, name, result, args):
        function = getattr(self.lib, name)
        function.restype, function.argtypes = result, args

    def outbound(self):
        session = Session(self, "outbound")
        try:
            size = self.lib.olm_init_outbound_group_session_random_length(session.ptr)
            # Deliberately reproducible, insecure entropy; NEVER use for real keys.
            entropy = c.create_string_buffer(bytes(i % 256 for i in range(size)))
            session.check(self.lib.olm_init_outbound_group_session(session.ptr, entropy, size))
            return session
        except Exception:
            session.close()
            raise

    def inbound(self, key, exported=False):
        session = Session(self, "inbound")
        try:
            function = (self.lib.olm_import_inbound_group_session if exported
                        else self.lib.olm_init_inbound_group_session)
            key = c.create_string_buffer(key)  # libolm may overwrite inputs.
            session.check(function(session.ptr, key, len(key.raw) - 1))
            return session
        except Exception:
            session.close()
            raise


class Session:
    def __init__(self, olm, direction):
        self.lib, self.direction = olm.lib, direction
        stem = "olm_" + direction + "_group_session"
        self.memory = c.create_string_buffer(getattr(self.lib, stem + "_size")())
        self.ptr = getattr(self.lib, stem)(self.memory)

    def check(self, result):
        if result == ERROR:
            error = getattr(self.lib, "olm_" + self.direction + "_group_session_last_error")
            raise OlmError(error(self.ptr).decode("ascii"))
        return result

    def output(self, length_function, function, *args):
        size = getattr(self.lib, length_function)(self.ptr)
        buffer = c.create_string_buffer(size)
        length = self.check(getattr(self.lib, function)(self.ptr, buffer, size, *args))
        return buffer.raw[:length]

    def session_id(self):
        stem = "olm_" + self.direction + "_group_session_id"
        return self.output(stem + "_length", stem).decode("ascii")

    def sharing_key(self):
        stem = "olm_outbound_group_session_key"
        return self.output(stem + "_length", stem)

    def export(self, index):
        stem = "olm_export_inbound_group_session"
        return self.output(stem + "_length", stem, index)

    def first_index(self):
        return self.lib.olm_inbound_group_session_first_known_index(self.ptr)

    def verified(self):
        # libolm internal flag, NOT Matrix device/sender verification.
        return bool(self.lib.olm_inbound_group_session_is_verified(self.ptr))

    def encrypt(self, plain):
        size = self.lib.olm_group_encrypt_message_length(self.ptr, len(plain))
        output = c.create_string_buffer(size)
        length = self.check(self.lib.olm_group_encrypt(
            self.ptr, c.create_string_buffer(plain), len(plain), output, size))
        return output.raw[:length]

    def decrypt(self, message):
        size = self.check(self.lib.olm_group_decrypt_max_plaintext_length(
            self.ptr, c.create_string_buffer(message), len(message)))
        output, index = c.create_string_buffer(size), c.c_uint32()
        length = self.check(self.lib.olm_group_decrypt(
            self.ptr, c.create_string_buffer(message), len(message),
            output, size, c.byref(index)))
        return output.raw[:length], index.value

    def close(self):
        if self.ptr:
            getattr(self.lib, "olm_clear_" + self.direction + "_group_session")(self.ptr)
            self.ptr = None

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()


def event(index):
    return json.dumps({"room_id": ROOM, "type": "m.room.message", "content": {
        "msgtype": "m.text", "body": "Synthetic message %d" % index,
    }}, sort_keys=True, separators=(",", ":")).encode()


def cloud_plaintext(session_id, key, kind, chain_index=0):
    """Fabricated common JSON fields; not a native Go exporter invocation."""
    return json.dumps({
        "version": "1", "room_id": ROOM, "group_session_id": session_id,
        "algorithm": "m.megolm.v1.aes-sha2", "type": kind,
        "group_session_key": key.decode("ascii"), "chain_index": chain_index,
        "sender": "@synthetic:example.invalid",
        "c25519": "synthetic-unverified-device-key",
        "ed25519": "synthetic-unverified-signing-key",
    }, sort_keys=True, separators=(",", ":")).encode()
