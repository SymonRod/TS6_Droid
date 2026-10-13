"""gdb script: dump myTeamSpeak RPC bodies in plaintext, inside the client.

Runs the isolated desktop client as a child of gdb (kernel.yama.ptrace_scope
= 1 forbids attaching later) and sets non-stopping breakpoints in
com::teamspeak::rpc::Channel's worker (see docs/myteamspeak-handoff.md):

  REQ   0x1dfd82a  call [rax+0x18]   HTTP POST: rsi = URL, rdx = body,
                                     rcx = ?, r8 = content type,
                                     r9 = response (filled by the call)
  RET   0x1dfd82d  after the call    response read back via the saved r9
  PARSE 0x1dfde0b  ParseFromString   rsi = data, rdx = length (cross-check)

Writes <run>-NNN-POST-<host>-<path>.{req,resp}.bin next to the log, the
layout tools/myts/analyze.py reads. The log holds metadata only (sizes,
URL, method name), never body bytes.

  MYTS_RUN=run6 gdb -batch -nx -x tools/myts/gdb_capture.py \\
      --args /opt/teamspeak/TeamSpeak
  MYTS_DRY=1 gdb -batch -nx -x tools/myts/gdb_capture.py   # checks, no run

Offsets are for the pinned build only; the script refuses anything else.
"""

import hashlib
import os
import re
import struct
import sys
import time

try:
    import gdb
except ImportError:  # py_compile / self-test outside gdb
    gdb = None

BINARY = "/opt/teamspeak/TeamSpeak"
BINARY_MD5 = "8234f961015da34f1387fa735a7443b0"
OFF_REQ = 0x1DFD82A
OFF_RET = 0x1DFD82D
OFF_PARSE = 0x1DFDE0B
OFF_PARSE_TARGET = 0x289F050
MAX_BLOB = 16 << 20

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.environ.get("MYTS_OUT", os.path.join(ROOT, "captures", "myts"))
RUN = os.environ.get("MYTS_RUN", "") or "run"


# --- libc++ std::string / std::vector<char> decoding -----------------------

def decode_string(read, ptr):
    """libc++ x86-64 std::string at ptr -> bytes, or None if implausible.

    byte 0 bit 0 set: long form, size at +8, data pointer at +16.
    clear: short form, size = byte0 >> 1 (<= 22), data inline at +1.
    """
    raw = read(ptr, 24)
    if raw is None:
        return None
    if raw[0] & 1:
        cap_word, size, data = struct.unpack("<QQQ", raw)
        cap = cap_word & ~1
        if size > MAX_BLOB or (cap and size > cap) or data < 0x1000:
            return None
        return read(data, size) if size else b""
    size = raw[0] >> 1
    if size > 22:
        return None
    return raw[1:1 + size]


def decode_vector(read, ptr):
    """std::vector<char> {begin, end, cap} at ptr -> bytes, or None."""
    raw = read(ptr, 24)
    if raw is None:
        return None
    begin, end, cap = struct.unpack("<QQQ", raw)
    if begin < 0x1000 or end < begin or (cap and cap < end):
        return None
    size = end - begin
    if size > MAX_BLOB:
        return None
    return read(begin, size) if size else b""


# --- filename helpers ------------------------------------------------------

_SLUG = re.compile(r"[^0-9A-Za-z._-]+")


def looks_like_url(data):
    """Cheap sanity gate: printable ASCII, plausible URL or path."""
    if not data or len(data) > 4096:
        return False
    try:
        text = data.decode("ascii")
    except UnicodeDecodeError:
        return False
    return text.startswith(("http://", "https://", "/"))


def split_url(url):
    """(host, path) from a URL or bare path; host '' when absent."""
    m = re.match(r"https?://([^/]+)(/.*)?$", url)
    if m:
        return m.group(1), m.group(2) or "/"
    return "", url


def slug(text, fallback):
    text = _SLUG.sub("_", text).strip("_")
    return text[:60] if text else fallback


# --- md5 of the pinned build ----------------------------------------------

def md5_of(path):
    h = hashlib.md5()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


# --- everything below needs a live gdb -------------------------------------

if gdb is not None:

    def read_mem(addr, n):
        """inferior bytes, or None on a bad/short read (never raises)."""
        if n <= 0:
            return b""
        try:
            return bytes(gdb.selected_inferior().read_memory(addr, n))
        except (gdb.MemoryError, gdb.error, OverflowError, ValueError):
            return None

    def reg(name):
        try:
            return int(gdb.newest_frame().read_register(name)) & 0xFFFFFFFFFFFFFFFF
        except (gdb.error, ValueError):
            return 0

    def tid():
        t = gdb.selected_thread()
        return t.global_num if t is not None else 0

    def log(msg):
        line = "[%.3f] %s" % (time.time(), msg)
        print(line, file=sys.stderr)
        try:
            with open(LOG_PATH, "a") as fh:
                fh.write(line + "\n")
        except OSError:
            pass

    def write_blob(name, data):
        path = os.path.join(OUT_DIR, name)
        with open(path, "wb") as fh:
            fh.write(data)
        return path

    LOG_PATH = os.path.join(OUT_DIR, RUN + "-gdb.log")
    STATE = {}          # thread id -> pending request context
    SEQ = [0]           # single mutable counter, shared across breakpoints

    # Registers to probe as std::string at REQ. rsi holds the URL; the body
    # (u8 len + method + protobuf) lives in one of these — we detect which.
    BODY_CANDIDATES = ("rdi", "rdx", "rcx", "r9", "r8")

    def framing_method(data):
        """If data starts with u8 len + that many printable bytes, return the
        method name; else None. Distinguishes the framed body from URLs etc."""
        if not data:
            return None
        n = data[0]
        if n == 0 or 1 + n > len(data):
            return None
        name = data[1:1 + n]
        if all(32 <= b < 127 for b in name):
            return name.decode("ascii")
        return None

    class ReqBreakpoint(gdb.Breakpoint):
        """HTTP POST about to be issued: find the framed body and dump it."""

        def stop(self):
            url_b = decode_string(read_mem, reg("rsi"))
            if not looks_like_url(url_b):
                log("REQ skipped: rsi=0x%x not a plausible URL" % reg("rsi"))
                return False
            url = url_b.decode("ascii")
            host, path = split_url(url)

            # Probe every candidate; prefer the one that looks framed.
            probes, body, body_reg, method = [], None, None, None
            for rn in BODY_CANDIDATES:
                s = decode_string(read_mem, reg(rn))
                if s is None:
                    probes.append("%s=?" % rn)
                    continue
                m = framing_method(s)
                probes.append("%s:%dB%s" % (rn, len(s), (":" + m) if m else ""))
                if m and body is None:
                    body, body_reg, method = s, rn, m
            if body is None:  # nothing framed: keep the largest non-empty probe
                best = max(
                    ((rn, decode_string(read_mem, reg(rn))) for rn in BODY_CANDIDATES),
                    key=lambda kv: len(kv[1]) if kv[1] else -1)
                body_reg, body = best[0], (best[1] or b"")

            SEQ[0] += 1
            seq = SEQ[0]
            base = "%s-%03d-POST-%s-%s" % (
                RUN, seq, slug(host, "nohost"), slug(path.lstrip("/"), "root"))
            write_blob(base + ".req.bin", body)
            STATE[tid()] = {"base": base, "url": url, "seq": seq, "resp_done": False}
            log("REQ #%03d thread=%d %s body<-%s method=%r %dB | %s"
                % (seq, tid(), url, body_reg, method, len(body), " ".join(probes)))
            return False  # never stop the client

    class RetBreakpoint(gdb.Breakpoint):
        """Call returned. Reply is captured at ParseFromString, not here."""

        def stop(self):
            return False

    class ParseBreakpoint(gdb.Breakpoint):
        """ParseFromString(rsi=data, rdx=len): the reply. First one after a
        REQ on this thread is that request's reply (order REQ->RET->PARSE)."""

        def stop(self):
            length, data_p = reg("rdx"), reg("rsi")
            ctx = STATE.get(tid())
            if ctx and not ctx["resp_done"] and 0 < length <= MAX_BLOB:
                data = read_mem(data_p, length)
                if data is not None:
                    write_blob(ctx["base"] + ".resp.bin", data)
                    ctx["resp_done"] = True
                    log("PARSE->resp #%03d thread=%d len=%d" % (ctx["seq"], tid(), length))
                    return False
            log("PARSE thread=%d len=%d (unmatched)" % (tid(), length))
            return False

    def load_base():
        """Runtime load address of the binary's first mapping (PIE base)."""
        out = gdb.execute("info proc mappings", to_string=True)
        best = None
        for line in out.splitlines():
            cols = line.split()
            if len(cols) >= 5 and cols[-1] == BINARY:
                try:
                    start = int(cols[0], 16)
                    off = int(cols[3], 16)
                except ValueError:
                    continue
                if off == 0 and (best is None or start < best):
                    best = start
        return best

    def install(base):
        for cls, off, tag in (
            (ReqBreakpoint, OFF_REQ, "REQ"),
            (RetBreakpoint, OFF_RET, "RET"),
            (ParseBreakpoint, OFF_PARSE, "PARSE"),
        ):
            bp = cls("*" + hex(base + off))
            bp.silent = True
            log("armed %s at 0x%x (base 0x%x + 0x%x)" % (tag, base + off, base, off))

    def preflight():
        problems = []
        if not os.path.exists(BINARY):
            problems.append("binary missing: %s" % BINARY)
        else:
            got = md5_of(BINARY)
            if got != BINARY_MD5:
                problems.append("md5 mismatch: got %s, want %s" % (got, BINARY_MD5))
        try:
            os.makedirs(OUT_DIR, exist_ok=True)
            probe = os.path.join(OUT_DIR, ".write-probe")
            open(probe, "w").close()
            os.unlink(probe)
        except OSError as e:
            problems.append("out dir not writable: %s (%s)" % (OUT_DIR, e))
        return problems

    def main():
        dry = bool(os.environ.get("MYTS_DRY"))
        problems = preflight()
        if problems:
            for p in problems:
                print("PREFLIGHT FAIL:", p, file=sys.stderr)
            if not dry:
                raise gdb.error("preflight failed; refusing to run")
        if dry:
            print("dry run OK: binary + offsets present, out dir %s writable"
                  % OUT_DIR, file=sys.stderr)
            return

        gdb.execute("set pagination off")
        gdb.execute("set confirm off")
        gdb.execute("set follow-fork-mode parent")
        gdb.execute("set detach-on-fork on")
        for sig in ("SIGPIPE", "SIGUSR1", "SIGUSR2",
                    "SIG32", "SIG33", "SIG34", "SIG35", "SIGPWR"):
            try:
                gdb.execute("handle %s nostop noprint pass" % sig)
            except gdb.error:
                pass

        gdb.execute("starti")           # stop at the first instruction
        base = load_base()
        if base is None:
            raise gdb.error("could not find load base for %s" % BINARY)
        log("run=%s base=0x%x pid=%s" % (RUN, base, gdb.selected_inferior().pid))
        install(base)
        gdb.execute("continue")         # runs until the client exits / gdb dies

    main()
