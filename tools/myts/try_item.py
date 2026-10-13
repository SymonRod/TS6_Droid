#!/usr/bin/env python3
"""Try captured run8 blobs/plaintexts as Item_Data (masked summary, no secrets).

    python3 tools/myts/try_item.py captures/myts/run8-item-001.blob.bin [...]

For each file: length + sha8, then attempt a parse as
``com.teamspeak.sync.proto.Item_Data``. On success prints only the
non-sensitive shape (which oneof content, item_type, manipulated, whether
string fields are present -- never their values). On failure prints the
protobuf error. Never prints key/iv/plaintext bytes.

Exit status: 0 if at least one file parses with a non-empty item_content,
1 otherwise (convenient for gating "task 1D blob side solved").
"""

import glob
import hashlib
import os
import subprocess
import sys
import tempfile

from google.protobuf import descriptor_pb2, descriptor_pool, message_factory

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PROTO_DIR = os.path.join(ROOT, "docs", "proto")


def load_item_cls():
    protos = sorted(os.path.basename(p) for p in glob.glob(os.path.join(PROTO_DIR, "*.proto")))
    with tempfile.NamedTemporaryFile(suffix=".pb") as out:
        subprocess.run(["protoc", f"-I{PROTO_DIR}", "--include_imports",
                        f"--descriptor_set_out={out.name}", *protos],
                       check=True, stderr=subprocess.DEVNULL)
        fds = descriptor_pb2.FileDescriptorSet.FromString(open(out.name, "rb").read())
    pool = descriptor_pool.DescriptorPool()
    for fd in fds.file:
        pool.Add(fd)
    return message_factory.GetMessageClass(
        pool.FindMessageTypeByName("com.teamspeak.sync.proto.Item_Data"))


def shape(item):
    """Masked one-line shape: field presence only, no string/bytes values."""
    present = sorted(f.name for f, _ in item.ListFields()
                     if f.type not in (f.TYPE_STRING, f.TYPE_BYTES, f.TYPE_MESSAGE))
    msgs = []
    for f, v in item.ListFields():
        if f.type == f.TYPE_MESSAGE and not f.message_type.GetOptions().map_entry:
            items = v if hasattr(f, "is_repeated") and f.is_repeated else [v]
            for sub in items:
                sub_present = sorted(sf.name for sf, _ in sub.ListFields()
                                     if sf.type not in (sf.TYPE_STRING, sf.TYPE_BYTES,
                                                        sf.TYPE_MESSAGE))
                n_bytes = sum(len(sv) for sf, sv in sub.ListFields()
                              if sf.type == sf.TYPE_BYTES for sv in
                              (sv if hasattr(sf, "is_repeated") and sf.is_repeated else [sv]))
                msgs.append("%s(scalars=%s,bytes=%dB)" % (f.name, sub_present, n_bytes))
    return "content=%s item_type=%s scalars=%s %s" % (
        item.WhichOneof("item_content"), item.item_type, present, " ".join(msgs))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        args = sorted(glob.glob("captures/myts/run8-item-*.blob.bin")
                      + glob.glob("captures/myts/run8-item-*.plain.bin")
                      + glob.glob("captures/myts/run8-dec-*.pt.bin"))
    item_cls = load_item_cls()
    ok = 0
    if not args:
        print("no input files (expected captures/myts/run8-*); capture a run8 first",
              file=sys.stderr)
        return 1
    for path in args:
        try:
            blob = open(path, "rb").read()
        except OSError as e:
            print(f"== {path}: unreadable ({e})")
            continue
        tag = hashlib.sha256(blob).hexdigest()[:8]
        try:
            item = item_cls.FromString(blob)
            content = item.WhichOneof("item_content")
            if content and item.IsInitialized():
                print(f"== {os.path.basename(path)} len={len(blob)} #{tag} "
                      f"-> CLEARTEXT {shape(item)}")
                ok += 1
            else:
                print(f"== {os.path.basename(path)} len={len(blob)} #{tag} "
                      f"-> parses but empty (no item_content)")
        except Exception as e:
            print(f"== {os.path.basename(path)} len={len(blob)} #{tag} "
                  f"-> undecodable ({e})")
    print(f"-- {ok}/{len(args)} files are non-empty Item_Data")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
