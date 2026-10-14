"""Build-pinned, isolated-profile account-key/crypto capture (run41).

Run under gdb as the client's parent; no late attach or system ptrace changes.
MYTS_BINARY selects the executable, MYTS_OUT a fresh ignored captures/ folder.
All buffers are secret local files (0600); logs contain only lengths and PCs.
The probe observes calls, never replaces results or changes account data.
"""

import hashlib
import os
from pathlib import Path
import struct

import gdb

ROOT = Path(__file__).resolve().parents[2]
BINARY = Path(os.environ.get("MYTS_BINARY", ROOT / "../teamspeak/TeamSpeak")).resolve()
OUT = Path(os.environ["MYTS_OUT"]).resolve()
EXPECTED_MD5 = "7eb9fdb89d3da783d3db55845c5066ca"
MAX_BUFFER = 1 << 20
BASE = 0
SEQUENCE = 0
REPLIES = {}

# Function entries checked with this build's unwind boundaries/disassembly.
# Tags describe observation points, not a claim about the final wire format.
FUNCTIONS = {
    "derive-encryption": (0x2A7FE30, (), 1),
    "verify-hash-wrapper": (0x2A7FFA0, ("rdx",), 1),
    "split-authenticated-blob": (0x2A82760, ("rdx", "rcx"), 1),
    "iv16-decrypt": (0x2A82E60, ("rdx",), 1),
    "sha512-string": (0x2A82110, ("rdx",), 1),
    "authenticated-core": (0x2A819B0, ("rdx", "rcx", "r8"), 2),
}


def read(address, length):
    if not 0 <= length <= MAX_BUFFER or address < 4096:
        return None
    try:
        return bytes(gdb.selected_inferior().read_memory(address, length))
    except (gdb.error, OverflowError, ValueError):
        return None


def string(address):
    raw = read(address, 24)
    if raw is None:
        return None
    if raw[0] & 1:
        capacity, length, data = struct.unpack("<QQQ", raw)
        if length > MAX_BUFFER or length > (capacity & ~1):
            return None
        return b"" if not length else read(data, length)
    length = raw[0] >> 1
    return raw[1:1 + length] if length <= 22 else None


def register(name):
    return int(gdb.newest_frame().read_register(name)) & ((1 << 64) - 1)


def log(message):
    with (OUT / "metadata.log").open("a") as stream:
        stream.write(message + "\n")


def dump(sequence, tag, name, data):
    if data is None:
        return -1
    path = OUT / ("%03d-%s-%s.bin" % (sequence, tag, name))
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(data)
    return len(data)


def backtrace():
    result = []
    frame = gdb.newest_frame()
    while frame and len(result) < 14:
        pc = frame.pc()
        library = gdb.solib_name(pc)
        result.append(Path(library).name if library else "0x%x" % (pc - BASE))
        frame = frame.older()
    return result


class Result(gdb.FinishBreakpoint):
    def __init__(self, sequence, tag, output, count):
        super().__init__(gdb.newest_frame(), internal=True)
        self.silent = True
        self.sequence, self.tag, self.output, self.count = sequence, tag, output, count

    def stop(self):
        try:
            lengths = [dump(self.sequence, self.tag, "result%d" % i,
                            string(self.output + i * 24)) for i in range(self.count)]
            log("%03d %s result_lengths=%s" % (self.sequence, self.tag, lengths))
        except Exception as error:
            log("PROBE_ERROR result %s" % type(error).__name__)
            return True
        return False

    def out_of_scope(self):
        log("PROBE_LOST %03d %s" % (self.sequence, self.tag))


class Entry(gdb.Breakpoint):
    def __init__(self, tag, offset, registers, count):
        super().__init__("*0x%x" % (BASE + offset), internal=True)
        self.silent = True
        self.tag, self.registers, self.count = tag, registers, count
        self.hits = 0

    def stop(self):
        global SEQUENCE
        try:
            self.hits += 1
            if self.hits > 200:
                self.enabled = False
                log("PROBE_LIMIT %s" % self.tag)
                return False
            SEQUENCE += 1
            sequence = SEQUENCE
            lengths = {name: dump(sequence, self.tag, name, string(register(name)))
                       for name in self.registers}
            log("%03d %s lengths=%s stack=%s" %
                (sequence, self.tag, lengths, backtrace()))
            if self.tag == "authenticated-core":
                log("%03d mode=%d" % (sequence, register("r9")))
            Result(sequence, self.tag, register("rdi"), self.count)
        except Exception as error:
            log("PROBE_ERROR entry %s" % type(error).__name__)
            return True
        return False


class HttpRequest(gdb.Breakpoint):
    def __init__(self):
        super().__init__("*0x%x" % (BASE + 0x46D9559), internal=True)
        self.silent = True

    def stop(self):
        global SEQUENCE
        try:
            url, body = string(register("rsi")), string(register("rcx"))
            if url is None or body is None or not body:
                return False
            name = body[1:1 + body[0]]
            allowed = {
                (b"https://clientapi.myteamspeak.com/authentication", b"login"),
                (b"https://clientapi.myteamspeak.com/synchronization", b"requestServerItems"),
            }
            if (url, name) not in allowed:
                return False
            SEQUENCE += 1
            tag = "http-" + name.decode("ascii")
            response = struct.unpack("<Q", read(register("rbx") + 0x48, 8))[0]
            REPLIES[response] = (SEQUENCE, tag)
            log("%03d %s request_length=%d" % (SEQUENCE, tag,
                dump(SEQUENCE, tag, "request", body)))
        except Exception as error:
            log("PROBE_ERROR http %s" % type(error).__name__)
            return True
        return False


class HttpParse(gdb.Breakpoint):
    def __init__(self):
        super().__init__("*0x%x" % (BASE + 0x46D9B2B), internal=True)
        self.silent = True

    def stop(self):
        try:
            selected = REPLIES.pop(register("rdi"), None)
            if selected is not None:
                sequence, tag = selected
                data = read(register("rsi"), register("rdx"))
                log("%03d %s http_status=200 reply_length=%d" %
                    (sequence, tag, dump(sequence, tag, "reply", data)))
        except Exception as error:
            log("PROBE_ERROR reply %s" % type(error).__name__)
            return True
        return False


def main():
    global BASE
    os.umask(0o077)
    assert OUT.is_relative_to(ROOT / "captures"), "unsafe output directory"
    assert hashlib.md5(BINARY.read_bytes()).hexdigest() == EXPECTED_MD5, "build mismatch"
    profile = Path(os.environ["XDG_CONFIG_HOME"]).resolve()
    assert profile.is_relative_to(ROOT / "captures"), "not a research profile"
    OUT.mkdir(mode=0o700, parents=True, exist_ok=True)
    assert not (OUT / "metadata.log").exists(), "use a fresh probe output directory"
    if os.environ.get("MYTS_DRY"):
        print("unwrap probe preflight OK (no client launch)")
        return
    assert Path(gdb.current_progspace().filename).resolve() == BINARY, "unexpected executable"
    for command in ("set pagination off", "set confirm off", "set print thread-events off",
                    "set follow-fork-mode parent", "set detach-on-fork on",
                    "set disable-randomization off"):
        gdb.execute(command)
    for sig in ("SIGPIPE", "SIGUSR1", "SIGUSR2", "SIG32", "SIG33", "SIG34", "SIG35", "SIGPWR"):
        gdb.execute("handle %s nostop noprint pass" % sig)
    gdb.execute("starti")
    pid = gdb.selected_inferior().pid
    with Path("/proc/%d/maps" % pid).open() as stream:
        BASE = next(int(line.split()[0].split("-")[0], 16) for line in stream
                    if line.rstrip().endswith(str(BINARY)) and line.split()[2] == "00000000")
    for tag, (offset, registers, count) in FUNCTIONS.items():
        Entry(tag, offset, registers, count)
    HttpRequest()
    HttpParse()
    log("READY pid=%d base=0x%x breakpoints=%d" % (pid, BASE, len(FUNCTIONS) + 2))
    try:
        gdb.execute("continue")
        if gdb.selected_inferior().pid:
            log("STOP stack=%s" % backtrace())
            log(gdb.execute("info program", to_string=True).strip())
    except KeyboardInterrupt:
        pass
    finally:
        if gdb.selected_inferior().pid:
            gdb.execute("detach")


main()
