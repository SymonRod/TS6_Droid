"""Build-pinned offline desktop oracle using ONLY generated synthetic identities.

Run in a fresh network namespace, before the application's main is entered:
  unshare -Urn env MYTS_HOST_NETNS="$(readlink /proc/self/ns/net)" \
    MYTS_BINARY=/path/TeamSpeak gdb -batch -nx \
    -x tools/myts/gdb_identity_synthetic.py /path/TeamSpeak

No attach, account, capture, login, UI or existing profile access. The inferior is killed
after calling the desktop's identity/UID helpers. Requires the existing research
venv for PyCryptodome (MYTS_PYTHON). Output contains only names/public metadata.
"""

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
EXPECTED_MD5 = "7eb9fdb89d3da783d3db55845c5066ca"
BASE = 0
STAGE = "preflight"


def call(offset, signature, arguments):
    return gdb.parse_and_eval("((%s)0x%x)(%s)" % (signature, BASE + offset, arguments))


def allocate(data):
    address = int(call(0x4A078F0, "void*(*)(unsigned long long)", str(max(len(data), 1))))
    assert address
    gdb.selected_inferior().write_memory(address, data)
    return address


def string_at(address):
    raw = bytes(gdb.selected_inferior().read_memory(address, 24))
    if raw[0] & 1:
        capacity, size, data = struct.unpack("<QQQ", raw)
        assert size < 4096 and size <= (capacity & ~1)
        return bytes(gdb.selected_inferior().read_memory(data, size))
    size = raw[0] >> 1
    assert size <= 22
    return raw[1:1 + size]


def cxx_string(data):
    pointer = allocate(data + b"\x00")
    return allocate(struct.pack("<QQQ", ((len(data) + 8) & ~7) | 1, len(data), pointer))


class StopOnExit(gdb.Breakpoint):
    def stop(self):
        frame = gdb.newest_frame()
        while frame:
            print("Unexpected exit PC 0x%x" % (frame.pc() - BASE))
            frame = frame.older()
        return True


def main():
    global BASE, STAGE
    assert hashlib.md5(BINARY.read_bytes()).hexdigest() == EXPECTED_MD5, "build mismatch"
    assert Path(gdb.current_progspace().filename).resolve() == BINARY
    # Fail closed unless the runner has isolated networking and unset GUI/profile
    # entry points. No application main or event loop is ever continued.
    assert os.readlink("/proc/self/ns/net") != os.environ["MYTS_HOST_NETNS"], "use unshare -Urn"
    with Path("/proc/net/dev").open() as stream:
        assert {line.split(":", 1)[0].strip() for line in stream if ":" in line} == {"lo"}, "network not isolated"
    STAGE = "generate synthetic vectors"
    code = ("import sys,json;sys.path.insert(0,%r);from identity_vectors import vectors;"
            "print(json.dumps([{k:v for k,v in x.items() if k != 'scalar'} for x in vectors()]))") % str(ROOT / "tools/myts")
    python = os.environ.get("MYTS_PYTHON", str(ROOT / "captures/myts/.venv/bin/python"))
    items = json.loads(subprocess.check_output([python, "-c", code]))
    STAGE = "stop before desktop main"
    profile = tempfile.mkdtemp(prefix="myts-synthetic-identity-", dir="/tmp/opencode")
    for command in ("set pagination off", "set confirm off", "set breakpoint pending on",
                    "set debuginfod enabled off",
                    "set print thread-events off", "set disable-randomization off",
                    "unset environment DISPLAY", "unset environment WAYLAND_DISPLAY",
                    "unset environment LD_PRELOAD", "set environment HOME " + profile,
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
        assert gdb.newest_frame().pc() == main_address, "did not reach the main-entry guard"
        pid = gdb.selected_inferior().pid
        with Path("/proc/%d/maps" % pid).open() as stream:
            BASE = next(int(line.split()[0].split("-")[0], 16) for line in stream
                        if line.rstrip().endswith(str(BINARY)) and line.split()[2] == "00000000")
        print("Desktop base=0x%x allocator=0x%x" % (BASE, BASE + 0x4A078F0))
        StopOnExit("exit", internal=True)
        StopOnExit("_exit", internal=True)
        StopOnExit("abort", internal=True)
        STAGE = "initialize desktop crypto descriptors"
        # Only the pure crypto setup from desktop init 0x26cbb50: copy its
        # built-in multiprecision descriptor and register its SHA-1 descriptor.
        # No algorithm/results are replaced; no connection/client init is run.
        call(0x4A07AD0, "void*(*)(void*,void*,unsigned long long)",
             "0x%x,0x%x,424" % (BASE + 0x4CB43D0, BASE + 0x4B30B70))
        assert int(call(0x3C428C0, "int(*)(void*)", "0x%x" % (BASE + 0x4B30900))) >= 0
        for item in items:
            STAGE = "synthetic desktop encoding: " + item["name"]
            raw = item["raw"].encode()
            encoded = cxx_string(raw)
            output = allocate(bytes(24))
            # Desktop obfuscator: sret string, input Base64(private DER), u64 offset.
            call(0x26FE000, "void(*)(void*,void*,unsigned long long)",
                 "0x%x,0x%x,%d" % (output, encoded, item["counter"]))
            assert string_at(output) == item["desktop"].encode(), "desktop encoding mismatch"
            STAGE = "synthetic desktop counter and UID: " + item["name"]
            identity = allocate(item["desktop"].encode() + b"\x00")
            counter_output = allocate(bytes(8))
            key_output = allocate(bytes(8))
            imported = call(0x26FD980, "unsigned char(*)(void*,unsigned long long,void*,void*)",
                            "0x%x,%d,0x%x,0x%x" % (identity, len(item["desktop"]), counter_output, key_output))
            assert bool(imported), "desktop private-key import failed"
            counter = struct.unpack("<Q", bytes(gdb.selected_inferior().read_memory(counter_output, 8)))[0]
            assert counter == item["counter"], "desktop counter mismatch"
            # Desktop API: char* identity, char** UID output; no client init needed.
            uid_pointer = allocate(bytes(8))
            status = int(call(0x26A2340, "unsigned int(*)(void*,void*)", "0x%x,0x%x" % (identity, uid_pointer)))
            assert status == 0, "desktop UID import failed (%d)" % status
            pointer = struct.unpack("<Q", bytes(gdb.selected_inferior().read_memory(uid_pointer, 8)))[0]
            uid = bytes(gdb.selected_inferior().read_memory(pointer, 28)).decode("ascii")
            assert uid == item["uid"], "desktop UID mismatch"
            print("PASS desktop encoding + counter + UID:", item["name"], "counter=%d" % counter, "uid=" + uid)
        print("PASS: 3 synthetic identities; desktop main never entered; network isolated")
    finally:
        if gdb.selected_inferior().pid:
            gdb.execute("kill")


try:
    main()
except Exception as error:
    # Do not emit exception values or inferior buffers, even on mismatch.
    print("FAIL synthetic desktop identity probe: stage=%s error=%s" % (STAGE, type(error).__name__))
    if isinstance(error, gdb.error):
        print("Debugger diagnostic:", str(error))
        if gdb.selected_inferior().pid:
            frame = gdb.newest_frame()
            while frame:
                print("PC 0x%x" % (frame.pc() - BASE))
                frame = frame.older()
    if gdb.selected_inferior().pid:
        gdb.execute("kill")
    gdb.execute("quit 1")
