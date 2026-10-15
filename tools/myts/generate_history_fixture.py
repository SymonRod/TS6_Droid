"""Public synthetic libolm -> Rust interoperability fixture; no accounts/network.

Run with the existing research venv and the pinned desktop libolm. The output
contains deliberately insecure deterministic keys and fabricated messages only.
"""
import base64
import json
import sys
from pathlib import Path

from chat_session_vectors import wrap
from megolm_synthetic import Olm, ROOM, event


def varint(n):
    result = bytearray()
    while n >= 128:
        result.append((n & 127) | 128)
        n >>= 7
    result.append(n)
    return bytes(result)


def field(n, value):
    if isinstance(value, str):
        value = value.encode()
    return varint(n * 8 + 2) + varint(len(value)) + value


def main():
    with Olm().outbound() as sender:
        messages = [sender.encrypt(event(i)).decode() for i in range(3)]
        key = sender.sharing_key().decode()
        messages += [sender.encrypt(event(i)).decode() for i in range(3, 6)]
        sid = sender.session_id()
    curve = base64.b64encode(bytes([42]) * 32).decode().rstrip("=")
    cloud = {
        "version": "1", "room_id": ROOM, "group_session_id": sid,
        "algorithm": "m.megolm.v1.aes-sha2", "type": 2,
        "group_session_key": key, "chain_index": 0,
        "sender": "@synthetic:example.invalid", "c25519": curve, "ed25519": sid,
    }
    data = {
        "provenance": "Synthetic pinned desktop libolm; account key bytes 0..31. NEVER use these keys outside tests.",
        "room": ROOM, "session": sid, "curve": curve, "cloud": cloud,
        "envelope": wrap(json.dumps(cloud, separators=(",", ":")).encode()).decode(),
        "events": [{
            "event_id": "$synthetic-%d" % i, "sender": cloud["sender"],
            "origin_server_ts": i, "type": "m.room.encrypted", "room_id": ROOM,
            "content": {"algorithm": cloud["algorithm"], "sender_key": curve,
                        "session_id": sid, "ciphertext": ciphertext},
        } for i, ciphertext in enumerate(messages)],
    }
    credentials = field(1, "example.invalid") + field(2, "reader") + field(3, "synthetic-chat-password")
    config = field(2, "synthetic-config") + field(21, field(5, credentials))
    encrypted_config = base64.b64decode(wrap(config))
    detail = field(1, "synthetic-config") + field(3, encrypted_config)
    reply = b"\x08" + varint(301) + field(2, b"\x08\x05" + field(3, detail))
    data["config_reply"] = base64.b64encode(reply).decode()
    output = Path(sys.argv[1])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(data, indent=2) + "\n")


if __name__ == "__main__":
    main()
