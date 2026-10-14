"""Small, build-pinned login/getter probe; logs metadata, never credentials.

Attach only to an explicitly selected research-profile process:
  MYTS_PID=... MYTS_OUT=... gdb -batch -nx -x tools/myts/gdb_login_probe.py
  MYTS_DRY=1 gdb -batch -nx -x tools/myts/gdb_login_probe.py

Requires ptrace permission. Dumps are sensitive and must stay in captures/.
Unlike the older all-syscall traps, only specific app functions are hooked.
"""

import hashlib
import os
import struct

import gdb

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BINARY = os.path.realpath(os.path.join(ROOT, "../teamspeak-client/TeamSpeak"))
EXPECTED_MD5 = "7eb9fdb89d3da783d3db55845c5066ca"
OUT = os.path.realpath(os.environ.get("MYTS_OUT", os.path.join(ROOT, "captures/myts/run39/probe")))
OFFSETS = {
    "http-request": 0x46D9559,  # rsi=URL std::string*, rcx=framed body*
    "account-getter": 0x2A5A820,
    "hash-wrapper": 0x2A7FFA0,
    "sha512-string": 0x2A82110,
    "encrypt-wrapper": 0x2A82C00,
    "derive-login": 0x2A7FC70,  # sret rdi, password string rsi, email string rdx
    "derive-encryption": 0x2A7FE30,
    "pbkdf2-strings": 0x2A83320,  # sret rdi, password rsi, salt rdx, length ecx, iterations r8d
}

SHA512_RAW = 0x47592B0  # (input pointer, input length, output pointer)


def read(address, size):
    try:
        return bytes(gdb.selected_inferior().read_memory(address, size))
    except (gdb.error, OverflowError):
        return None


def string(address):
    raw = read(address, 24)
    if raw is None:
        return None
    if raw[0] & 1:
        cap, size, data = struct.unpack("<QQQ", raw)
        if size > 4096 or size > (cap & ~1) or data < 4096:
            return None
        return read(data, size)
    size = raw[0] >> 1
    return raw[1:1 + size] if size <= 22 else None


def log(message):
    with open(os.path.join(OUT, "metadata.log"), "a") as stream:
        stream.write(message + "\n")
    print(message)


class StringResult(gdb.FinishBreakpoint):
    def __init__(self, frame, tag, pointer, number):
        super().__init__(frame, internal=True)
        self.tag, self.pointer, self.capture_number = tag, pointer, number
        self.silent = True

    def stop(self):
        data = string(self.pointer)
        if data is not None:
            path = os.path.join(OUT, "%03d-%s-result.bin" % (self.capture_number, self.tag))
            with open(path, "wb") as stream:
                stream.write(data)
            os.chmod(path, 0o600)
            log("%03d %s result length=%d" % (self.capture_number, self.tag, len(data)))
        return False


class Probe(gdb.Breakpoint):
    count = 0

    def __init__(self, tag, address, base):
        super().__init__("*0x%x" % address, internal=True)
        self.tag, self.base = tag, base
        self.silent = True

    def stop(self):
        Probe.count += 1
        if Probe.count > 100:
            self.enabled = False
            return False
        frame = gdb.newest_frame()
        if self.tag in ("derive-login", "derive-encryption", "pbkdf2-strings"):
            StringResult(frame, self.tag, int(frame.read_register("rdi")), Probe.count)
        if self.tag == "pbkdf2-strings":
            log("%03d pbkdf2 parameters output_bytes=%d iterations=%d" % (
                Probe.count, int(frame.read_register("ecx")), int(frame.read_register("r8d"))))
        lengths = {}
        for name in ["rsi", "rdx", "rcx"]:
            pointer = int(frame.read_register(name)) & ((1 << 64) - 1)
            data = string(pointer)
            if data:
                path = os.path.join(OUT, "%03d-%s-%s.bin" % (Probe.count, self.tag, name))
                with open(path, "wb") as stream:
                    stream.write(data)
                os.chmod(path, 0o600)
                lengths[name] = len(data)
        stack = []
        while frame and len(stack) < 15:
            pc = frame.pc()
            library = gdb.solib_name(pc)
            stack.append(os.path.basename(library) if library else "0x%x" % (pc - self.base))
            frame = frame.older()
        log("%03d %s lengths=%s stack=%s" % (Probe.count, self.tag, lengths, stack))
        return False


class RawShaProbe(gdb.Breakpoint):
    def __init__(self, base):
        super().__init__("*0x%x" % (base + SHA512_RAW), internal=True)
        self.base = base
        self.silent = True

    def stop(self):
        frame = gdb.newest_frame()
        length = int(frame.read_register("rsi"))
        if not 0 < length <= 4096:
            return False
        data = read(int(frame.read_register("rdi")), length)
        if data is None:
            return False
        Probe.count += 1
        if Probe.count > 100:
            self.enabled = False
            return False
        path = os.path.join(OUT, "%03d-sha512-input.bin" % Probe.count)
        with open(path, "wb") as stream:
            stream.write(data)
        os.chmod(path, 0o600)
        stack = []
        while frame and len(stack) < 15:
            pc = frame.pc()
            library = gdb.solib_name(pc)
            stack.append(os.path.basename(library) if library else "0x%x" % (pc - self.base))
            frame = frame.older()
        log("%03d sha512-raw length=%d stack=%s" % (Probe.count, length, stack))
        return False


def main():
    with open(BINARY, "rb") as stream:
        assert hashlib.md5(stream.read()).hexdigest() == EXPECTED_MD5, "build mismatch"
    assert OUT.startswith(os.path.join(ROOT, "captures") + os.sep), "unsafe capture directory"
    os.makedirs(OUT, mode=0o700, exist_ok=True)
    if os.environ.get("MYTS_DRY"):
        print("preflight OK (no attach)")
        return
    pid = int(os.environ["MYTS_PID"])
    with open("/proc/%d/environ" % pid, "rb") as stream:
        env = stream.read().split(b"\0")
    assert any(item.startswith(("XDG_CONFIG_HOME=" + os.path.join(ROOT, "captures") + "/").encode()) for item in env), "not a research profile"
    assert os.path.realpath("/proc/%d/exe" % pid) == BINARY, "unexpected process binary"
    gdb.execute("set pagination off")
    gdb.execute("set confirm off")
    gdb.execute("set print thread-events off")
    gdb.execute("attach %d" % pid)
    try:
        with open("/proc/%d/maps" % pid) as stream:
            base = next(int(line.split()[0].split("-")[0], 16) for line in stream
                        if line.rstrip().endswith(BINARY) and line.split()[2] == "00000000")
        for tag, offset in OFFSETS.items():
            Probe(tag, base + offset, base)
        RawShaProbe(base)
        log("attached targeted probe (%d breakpoints); interrupt debugger to detach" % (len(OFFSETS) + 1))
        try:
            gdb.execute("continue")
        except KeyboardInterrupt:
            pass
    finally:
        if gdb.selected_inferior().pid:
            gdb.execute("detach")


main()
