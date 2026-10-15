"""Build-pinned offline oracle for the desktop's cloud-chat envelope helpers.

Only generated synthetic keys/plaintexts; no login, real profile or network.
Stop before application main, initialize a V2 provider with a public key, and
check both native-decrypt/reference-encrypt and the reverse direction.

unshare -Urn env MYTS_HOST_NETNS="$(readlink /proc/self/ns/net)" \
  MYTS_BINARY="$PWD/../teamspeak/TeamSpeak" \
  gdb -batch -nx -x tools/myts/gdb_chat_session_synthetic.py ../teamspeak/TeamSpeak
"""

import base64
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile

import gdb


ROOT = Path(__file__).resolve().parents[2]
BINARY = Path(os.environ["MYTS_BINARY"]).resolve()
EXPECTED_SHA256 = "1189672c2c290997a419100b0f29f4da95d0df9d1e744b07a764eba1e8a0944f"
BASE = 0
STAGE = "preflight"


def call(offset, signature, arguments):
    return gdb.parse_and_eval("((%s)0x%x)(%s)" % (signature, BASE + offset, arguments))


def allocate(data):
    pointer = int(call(0x4A078F0, "void*(*)(unsigned long long)", str(max(len(data), 1))))
    assert pointer
    gdb.selected_inferior().write_memory(pointer, data)
    return pointer


def string_at(pointer):
    raw = bytes(gdb.selected_inferior().read_memory(pointer, 24))
    if raw[0] & 1:
        capacity, size, data = struct.unpack("<QQQ", raw)
        assert size <= 8192 and size <= (capacity & ~1)
        return bytes(gdb.selected_inferior().read_memory(data, size))
    size = raw[0] >> 1
    assert size <= 22
    return raw[1:1 + size]


def cxx_string(data):
    pointer = allocate(data + b"\x00")
    return allocate(struct.pack("<QQQ", ((len(data) + 8) & ~7) | 1, len(data), pointer))


def main():
    global BASE, STAGE
    assert hashlib.sha256(BINARY.read_bytes()).hexdigest() == EXPECTED_SHA256, "build mismatch"
    assert Path(gdb.current_progspace().filename).resolve() == BINARY
    assert os.readlink("/proc/self/ns/net") != os.environ["MYTS_HOST_NETNS"], "use unshare -Urn"
    with Path("/proc/net/dev").open() as stream:
        assert {line.split(":", 1)[0].strip() for line in stream if ":" in line} == {"lo"}
    python = os.environ.get("MYTS_PYTHON", str(ROOT / "captures/myts/.venv/bin/python"))
    code = ("import sys,json;sys.path.insert(0,%r);"
            "from chat_session_vectors import vectors,wrap;"
            "print(json.dumps([{'name':v['name'],'plain':v['plain'].hex(),"
            "'wrapped':wrap(v['plain']).decode()} for v in vectors()]))") % str(ROOT / "tools/myts")
    items = json.loads(subprocess.check_output([python, "-c", code]))
    STAGE = "stop before desktop main"
    profile = tempfile.mkdtemp(prefix="myts-synthetic-chat-", dir="/tmp/opencode")
    for command in ("set pagination off", "set confirm off", "set breakpoint pending on",
                    "set debuginfod enabled off", "set print thread-events off",
                    "set disable-randomization off", "unset environment DISPLAY",
                    "unset environment WAYLAND_DISPLAY", "unset environment LD_PRELOAD",
                    "set environment HOME " + profile,
                    "set environment XDG_CONFIG_HOME " + profile,
                    "set environment XDG_CACHE_HOME " + profile,
                    "set environment XDG_DATA_HOME " + profile):
        gdb.execute(command)
    startup = gdb.Breakpoint("__libc_start_main", internal=True)
    try:
        gdb.execute("run")
        main_address = int(gdb.newest_frame().read_register("rdi"))
        startup.delete()
        gdb.Breakpoint("*0x%x" % main_address, internal=True, temporary=True)
        gdb.execute("continue")
        assert gdb.newest_frame().pc() == main_address
        pid = gdb.selected_inferior().pid
        with Path("/proc/%d/maps" % pid).open() as stream:
            BASE = next(int(line.split()[0].split("-")[0], 16) for line in stream
                        if line.rstrip().endswith(str(BINARY)) and line.split()[2] == "00000000")
        STAGE = "construct synthetic V2 provider"
        provider = allocate(bytes(64))
        call(0x2A81F80, "void(*)(void*)", "0x%x" % provider)
        key = cxx_string(bytes(range(32)))
        assert int(call(0x2A830E0, "unsigned char(*)(void*,void*)", "0x%x,0x%x" % (provider, key)))
        # Encryption holds its provider at +0. No account/login object is needed.
        encryption = allocate(struct.pack("<Q", provider) + bytes(56))
        for item in items:
            STAGE = "native cloud decrypt: " + item["name"]
            encoded = cxx_string(item["wrapped"].encode())
            output = allocate(bytes(24))
            call(0x2A80780, "void(*)(void*,void*,void*)",
                 "0x%x,0x%x,0x%x" % (output, encryption, encoded))
            assert string_at(output) == bytes.fromhex(item["plain"]), "native plaintext mismatch"
            STAGE = "native cloud encrypt: " + item["name"]
            plain = cxx_string(bytes.fromhex(item["plain"]))
            encrypted = allocate(bytes(24))
            call(0x2A80700, "void(*)(void*,void*,void*)",
                 "0x%x,0x%x,0x%x" % (encrypted, encryption, plain))
            wrapped = string_at(encrypted)
            base64.b64decode(wrapped, validate=True)
            # Pipe only fabricated data to the independent reference implementation.
            verify = ("import sys;sys.path.insert(0,%r);from chat_session_vectors import unwrap;"
                      "print(unwrap(sys.stdin.buffer.read()).hex())") % str(ROOT / "tools/myts")
            result = subprocess.check_output([python, "-c", verify], input=wrapped).decode().strip()
            assert result == item["plain"], "reference plaintext mismatch"
            print("PASS native/reference cloud envelope:", item["name"])
        STAGE = "native negative envelope cases"
        blob = bytearray(base64.b64decode(items[0]["wrapped"], validate=True))
        damaged = []
        for position in (0, 16, len(blob) - 1):
            value = blob.copy()
            value[position] ^= 1
            damaged.append(base64.b64encode(value))
        damaged.append(base64.b64encode(bytes(80)))
        for value in damaged:
            output = allocate(bytes(24))
            encoded = cxx_string(value)
            call(0x2A80780, "void(*)(void*,void*,void*)",
                 "0x%x,0x%x,0x%x" % (output, encryption, encoded))
            assert string_at(output) == b"", "native accepted a damaged envelope"
        wrong_key = cxx_string(bytes(reversed(range(32))))
        assert int(call(0x2A830E0, "unsigned char(*)(void*,void*)",
                        "0x%x,0x%x" % (provider, wrong_key)))
        output = allocate(bytes(24))
        encoded = cxx_string(items[0]["wrapped"].encode())
        call(0x2A80780, "void(*)(void*,void*,void*)",
             "0x%x,0x%x,0x%x" % (output, encryption, encoded))
        assert string_at(output) == b"", "native accepted a wrong account key"
        print("PASS native rejects changed IV/ciphertext/digest, truncation and wrong key")
        print("PASS: 3 synthetic envelopes, both directions, 5 negative cases; no account/network; desktop main never entered")
    finally:
        if gdb.selected_inferior().pid:
            gdb.execute("kill")


try:
    main()
except Exception as error:
    print("FAIL synthetic desktop chat probe: stage=%s error=%s" % (STAGE, type(error).__name__))
    if gdb.selected_inferior().pid:
        gdb.execute("kill")
    gdb.execute("quit 1")
