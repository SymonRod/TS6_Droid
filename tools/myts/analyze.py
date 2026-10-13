#!/usr/bin/env python3
"""Decode captured myTeamSpeak RPCs with the recovered schemas.

    python3 tools/myts/analyze.py captures/myts/run3 [--raw]

Reads every <prefix>-NNN-*.req.bin / .resp.bin pair written by
capture_addon.py, strips the RPC framing (u8 length + method name), picks
request/reply types from the service descriptors in docs/proto/, and prints
both messages. Sync replies additionally get every item_blob tried as a
com.teamspeak.sync.proto.Item_Data: that answers capture question Q4
(cleartext vs encrypted items).

Credentials, tokens, sessions, emails, keys and blobs are masked (length +
short hash) unless --raw is given. Never paste --raw output into docs.
"""

import glob
import hashlib
import math
import os
import re
import subprocess
import sys
import tempfile
from collections import Counter

from google.protobuf import descriptor_pb2, descriptor_pool, message_factory, text_format

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PROTO_DIR = os.path.join(ROOT, "docs", "proto")
SENSITIVE = re.compile(
    r"password|token|session|email|key|secret|otp|device_id|mytsid|uuid|"
    r"passphrase|cert|signature|blob|identity|push|phone|iv$|tag$",
    re.I)


def load_pool():
    protos = sorted(os.path.basename(p) for p in glob.glob(os.path.join(PROTO_DIR, "*.proto")))
    with tempfile.NamedTemporaryFile(suffix=".pb") as out:
        subprocess.run(["protoc", f"-I{PROTO_DIR}", "--include_imports",
                        f"--descriptor_set_out={out.name}", *protos],
                       check=True, stderr=subprocess.DEVNULL)
        fds = descriptor_pb2.FileDescriptorSet.FromString(open(out.name, "rb").read())
    pool = descriptor_pool.DescriptorPool()
    for fd in fds.file:
        pool.Add(fd)
    methods = {}
    for fd in fds.file:
        for svc in fd.service:
            for m in svc.method:
                methods.setdefault(m.name, (svc.name, m.input_type[1:], m.output_type[1:]))
    return pool, methods


def cls(pool, name):
    return message_factory.GetMessageClass(pool.FindMessageTypeByName(name))


def entropy(b):
    if not b:
        return 0.0
    counts = Counter(b)
    return -sum(c / len(b) * math.log2(c / len(b)) for c in counts.values())


def mask(value):
    raw = value if isinstance(value, bytes) else str(value).encode()
    return f"<{len(raw)}B #{hashlib.sha256(raw).hexdigest()[:8]}>"


def repeated(field):
    # protobuf >= 7 dropped FieldDescriptor.label
    if hasattr(field, "is_repeated"):
        return field.is_repeated
    return field.label == field.LABEL_REPEATED


def redact(msg, raw):
    if raw:
        return msg
    for field, value in list(msg.ListFields()):
        if field.message_type is not None:
            items = value if repeated(field) else [value]
            for item in items:
                if not field.message_type.GetOptions().map_entry:
                    redact(item, raw)
        elif SENSITIVE.search(field.name) and field.type in (field.TYPE_STRING, field.TYPE_BYTES):
            if repeated(field):
                masked = [mask(v) for v in value]
                del value[:]
                if field.type == field.TYPE_STRING:
                    value.extend(masked)
            else:
                m = mask(value)
                setattr(msg, field.name, m if field.type == field.TYPE_STRING else m.encode())
    return msg


def show(title, msg, raw):
    text = text_format.MessageToString(redact(msg, raw), as_utf8=True)
    print(f"  {title} {msg.DESCRIPTOR.full_name}:")
    for line in (text.rstrip() or "(empty)").splitlines():
        print(f"    {line}")


def check_items(pool, reply, raw):
    """Q4: is item_blob a cleartext Item_Data?"""
    item_cls = cls(pool, "com.teamspeak.sync.proto.Item_Data")
    for c in getattr(reply, "classes", []):
        for d in c.detail:
            blob = d.item_blob
            if not blob:
                continue
            verdict = "undecodable"
            try:
                item = item_cls.FromString(blob)
                content = item.WhichOneof("item_content")
                if content and item.IsInitialized():
                    verdict = f"CLEARTEXT Item_Data ({content})"
            except Exception:
                pass
            print(f"  item class={c.itemclass} blob={len(blob)}B "
                  f"entropy={entropy(blob):.2f} bits/B head={blob[:16].hex()} -> {verdict}")
            if verdict.startswith("CLEARTEXT"):
                show("    item", item, raw)


def main():
    raw = "--raw" in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    prefix = args[0] if args else "captures/myts/run"
    pool, methods = load_pool()
    for req_path in sorted(glob.glob(f"{prefix}-*.req.bin")):
        resp_path = req_path[:-len(".req.bin")] + ".resp.bin"
        body = open(req_path, "rb").read()
        resp = open(resp_path, "rb").read() if os.path.exists(resp_path) else b""
        print(f"== {os.path.basename(req_path)[:-8]}  req={len(body)}B resp={len(resp)}B")
        n = body[0] if body else 0
        name = body[1:1 + n].decode("ascii", "replace")
        if name not in methods:
            print(f"  not a known RPC (first bytes {body[:24].hex()})")
            continue
        svc, in_type, out_type = methods[name]
        print(f"  rpc {svc}.{name}")
        try:
            show("request", cls(pool, in_type).FromString(body[1 + n:]), raw)
        except Exception as e:
            print(f"  request does not parse as {in_type}: {e}")
        try:
            reply = cls(pool, out_type).FromString(resp)
            if out_type.endswith("Sync_Reply_ItemClasses"):
                check_items(pool, reply, raw)
            show("reply", reply, raw)
        except Exception as e:
            print(f"  reply does not parse as {out_type}: {e} (head {resp[:24].hex()})")


if __name__ == "__main__":
    main()
