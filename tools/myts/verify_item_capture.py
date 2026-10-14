#!/usr/bin/env python3
"""Reproduce run41b sync decryption offline, with secret-free output.

Correlates each server item to native IV16 input, plaintext and SHA512 output;
opens the account key from the captured login and compares all item bytes.
No network, credentials, output plaintext files, or real-data fixtures.
"""

import argparse
import hashlib
import hmac
from pathlib import Path

from google.protobuf import any_pb2, descriptor_pb2, descriptor_pool, message_factory

from item import ItemError, decrypt_item
from item_vectors import ACCOUNT_KEY, BOOKMARK_BLOB
from unwrap import unwrap_account_key


def message_classes(directory):
    """Load this build's descriptors into a private pool, not the default pool."""
    pool = descriptor_pool.DescriptorPool()
    pool.AddSerializedFile(any_pb2.DESCRIPTOR.serialized_pb)
    descriptors = {}
    for path in directory.glob("*.descriptor.bin"):
        desc = descriptor_pb2.FileDescriptorProto.FromString(path.read_bytes())
        descriptors[desc.name] = desc

    def add(name):
        try:
            pool.FindFileByName(name)
            return
        except KeyError:
            pass
        desc = descriptors[name]
        for dep in desc.dependency:
            add(dep)
        pool.Add(desc)

    for name in ("myteamspeak_common.proto", "synchronization_common.proto",
                 "Sync_Serializing.proto"):
        add(name)
    names = {
        "login": "com.teamspeak.myteamspeak.proto.LoginSession",
        "reply": "com.teamspeak.myteamspeak.proto.synchronization.Sync_Reply_ItemClasses",
        "item": "com.teamspeak.sync.proto.Item_Data",
    }
    return {name: message_factory.GetMessageClass(pool.FindMessageTypeByName(full))
            for name, full in names.items()}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify(capture, descriptors):
    messages = message_classes(descriptors)
    # Check the fabricated golden against recovered schema, including proto2
    # presence of zero scalars and default-true send_mytsid_on_server.
    synthetic = messages["item"].FromString(decrypt_item(BOOKMARK_BLOB, ACCOUNT_KEY))
    require(synthetic.WhichOneof("item_content") == "bookmark" and
            synthetic.item_uuid == "synthetic-item" and
            synthetic.sync_version_uuid == "synthetic-version" and
            synthetic.manipulated == 3 and synthetic.HasField("item_type") and
            synthetic.item_type == 0, "synthetic Item_Data schema mismatch")
    require(synthetic.bookmark.name == "Synthetic bookmark" and
            synthetic.bookmark.address == "voice.example.invalid" and
            synthetic.bookmark.port == 9987 and
            synthetic.bookmark.nickname == "Alice 🔑" and
            synthetic.bookmark.server_password == "synthetic password" and
            synthetic.bookmark.default_channel == "Lobby" and
            synthetic.bookmark.send_mytsid_on_server and
            not synthetic.bookmark.HasField("connect_muted"),
            "synthetic Bookmark_Data schema mismatch")
    print("synthetic bookmark protobuf fields/presence: OK")
    read = lambda name: (capture / name).read_bytes()
    login = messages["login"].FromString(read("002-http-login-reply.bin"))
    require(login.error == 200 and bool(login.session), "unsuccessful login capture")
    account = unwrap_account_key(login.key, read("001-derive-encryption-result0.bin"))
    require(hmac.compare_digest(account, read("003-split-authenticated-blob-result0.bin")),
            "account unwrap/native mismatch")
    reply = messages["reply"].FromString(read("009-http-requestServerItems-reply.bin"))
    require(reply.status == 301, "unexpected captured sync status")
    count = bookmarks = 0
    matched = set()
    for group in reply.classes:
        for detail in group.detail:
            require(not detail.item_delte_on_server and bool(detail.item_blob),
                    "unsupported captured deletion/empty item")
            blob = detail.item_blob
            native = [p for p in capture.glob("*-iv16-decrypt-rdx.bin")
                      if hmac.compare_digest(p.read_bytes(), blob[:-64])]
            require(len(native) == 1, "ambiguous server/native input correlation")
            path = native[0]
            require(path not in matched, "duplicate native correlation")
            matched.add(path)
            plain = decrypt_item(blob, account)
            require(hmac.compare_digest(plain, path.with_name(
                path.name.replace("-rdx.bin", "-result0.bin")).read_bytes()),
                "offline/native plaintext mismatch")
            sequence = int(path.name.split("-", 1)[0]) + 1
            require(hmac.compare_digest(plain, read("%03d-sha512-string-rdx.bin" % sequence)),
                    "native digest input mismatch")
            require(hmac.compare_digest(blob[-64:], read(
                "%03d-sha512-string-result0.bin" % sequence)), "native digest output mismatch")
            require(hmac.compare_digest(blob[-64:], hashlib.sha512(plain).digest()),
                    "plaintext digest mismatch")
            item = messages["item"].FromString(plain)
            content = item.WhichOneof("item_content")
            require(item.IsInitialized() and bool(content), "invalid decrypted Item_Data")
            require(item.item_uuid == detail.item_uuid, "decrypted/outer item UUID mismatch")
            expected = {0: "bookmark", 1: "identity", 5: "config"}
            require(expected.get(group.itemclass) == content, "class/content mismatch")
            # Never assume sync_version_uuid equals the outer item_version: it
            # does not in this capture. Version/cursor semantics remain separate.
            for index in (0, 16, len(blob) - 1):
                damaged = bytearray(blob)
                damaged[index] ^= 1
                try:
                    decrypt_item(bytes(damaged), account)
                except ItemError:
                    pass
                else:
                    raise ValueError("altered item accepted")
            print("item=%d class=%d blob_bytes=%d plain_bytes=%d content=%s native/digest/UUID=OK" %
                  (count + 1, group.itemclass, len(blob), len(plain), content))
            count += 1
            bookmarks += content == "bookmark"
    require(count == 8 and bookmarks == 5, "unexpected run41b item coverage")
    print("verified_items=%d verified_bookmarks=%d; altered IV/ciphertext/digest rejected" %
          (count, bookmarks))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture", type=Path, required=True)
    parser.add_argument("--descriptors", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    try:
        for path in (args.capture, args.descriptors):
            require(path.resolve().is_relative_to(root / "captures"), "unsafe input directory")
        verify(args.capture, args.descriptors)
    except Exception as error:
        # Protobuf/library exceptions may include data. Never render them.
        print("offline item verification failed (%s); secret details suppressed" % type(error).__name__)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
