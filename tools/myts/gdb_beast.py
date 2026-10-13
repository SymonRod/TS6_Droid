"""gdb script: catch the Beast/JSON login path during a logout+login cycle.

Extends the run6 tool (tools/myts/gdb_capture.py, same pinned-build guard,
same libc++ decoders, same .req/.resp.bin layout) with breakpoints on the
Beast JSON-response handler block found statically in run22:

  FUN_01dacba0 @ 0x1dacba0 (+ siblings 0x1dacab0..0x1dada90)

These are async response callbacks (HTTP status == 200 -> JSON parse ->
continuation). The login reply must pass through one of them. ABI unknown,
so every hit dumps all six argument registers as attempted std::string /
vector<char> plus metadata (timestamps for cohort correlation with the
run21 login burst shape). Log holds metadata only, never body bytes.

Usage (AFTER user confirms; drives the UI by hand: log OUT, log back IN
with the throwaway account; NO profile wipe needed):

  MYTS_RUN=run22 gdb -batch -nx -x tools/myts/gdb_beast.py \\
      --args /opt/teamspeak/TeamSpeak
  MYTS_DRY=1 gdb -batch -nx -x tools/myts/gdb_beast.py   # checks, no run

Profile: point XDG_CONFIG_HOME/XDG_CACHE_HOME at captures/myts/profile-run22
(the run22 copy). The live isolated client (profile/) and the normal
instance are never touched; verify via /proc/<pid>/environ as usual.
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
OFF_PARSE_ENTRY = 0x289F050
OFF_DISPATCH_ENTRY = 0x1D45E10
OFF_DISPATCH_PARSE = 0x1D460B0
# Request path (run36): live TLS sender spine for app-data writes
# (597B write -> SSL/crypto cluster). Entry breakpoints dump the caller's
# plaintext buffers via the generic probe (framed/json/raw best-buffer).
OFF_REQPATH = (
    0x239B7F0,  # big writer (char*(p1..p4)) below the state machine
    0x2336600,  # handshake/record state machine entry (recursive)
)
# Run22 Beast JSON-response handler block (Ghidra addrs; PIE -> + load base).
# 0x1dacba0 is the fully-reversed callback (status==200 -> JSON parse);
# the rest are the sibling slots of the 40-entry handler table dumped from
# .data.rel.ro 0x3eff9a0 (run22 static). 0x1332F30 + 0x816xxx are the odd
# table entries outside the 0x1da block; data slots are skipped at arm time.
OFF_HANDLERS = (
    0x1DACA40,
    0x1DACAB0,
    0x1DACB20,
    0x1DACBA0,
    0x1DADA30,
    0x1DADA50,
    0x1DADA60,
    0x1DADA70,
    0x1DADA90,
    0x1DADAA0,
    0x1DADAB0,
    0x1DADAC0,
    0x1DADAD0,
    0x1DADAF0,
    0x1DADB00,
    0x1DADB80,
    0x1DADC00,
    0x1DADC90,
    0x1DADD00,
    0x1DADD70,
    0x1DADDF0,
    0x1DADE70,
    0x1DADE90,
    0x1DADEA0,
    0x1332F30,
    0x816B34,
    0x816CC1,
    0x816E12,
    0x816F01,
    0x816FCE,
    0x8170EC,
)
MAX_BLOB = 16 << 20

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.environ.get("MYTS_OUT", os.path.join(ROOT, "captures", "myts"))
RUN = os.environ.get("MYTS_RUN", "") or "run22"


def decode_string(read, ptr):
    """libc++ x86-64 std::string at ptr -> bytes, or None if implausible."""
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


_SLUG = re.compile(r"[^0-9A-Za-z._-]+")


def looks_like_url(data):
    if not data or len(data) > 4096:
        return False
    try:
        text = data.decode("ascii")
    except UnicodeDecodeError:
        return False
    return text.startswith(("http://", "https://", "/"))


def split_url(url):
    m = re.match(r"https?://([^/]+)(/.*)?$", url)
    if m:
        return m.group(1), m.group(2) or "/"
    return "", url


def slug(text, fallback):
    text = _SLUG.sub("_", text).strip("_")
    return text[:60] if text else fallback


def looks_like_json(data):
    if not data or len(data) > MAX_BLOB:
        return False
    s = data[:1]
    return s in (b"{", b"[")


def login_session_shape(data):
    """Minimal protobuf wire walk: returns (key_len, session_len) iff the
    buffer has field 1 = bytes in [40, 80] and field 2 = string of mostly
    printable ASCII in [30, 64] (LoginSession{key=1, session=2}). Pure
    python, no protobuf dependency (gdb's interpreter lacks it)."""
    pos, end = 0, len(data)
    have1, have2 = None, None
    while pos < end:
        b0 = data[pos]
        pos += 1
        fn, wt = b0 >> 3, b0 & 7
        if fn == 0:
            return None
        if wt == 0:
            while pos < end and data[pos] & 0x80:
                pos += 1
            pos += 1
            if pos > end:
                return None
        elif wt == 2:
            ln, sh = 0, 0
            while True:
                if pos >= end:
                    return None
                bb = data[pos]
                pos += 1
                ln |= (bb & 0x7f) << sh
                if not bb & 0x80:
                    break
                sh += 7
                if sh > 63:
                    return None
            if pos + ln > end:
                return None
            if fn == 1 and have1 is None:
                have1 = data[pos:pos + ln]
            elif fn == 2 and have2 is None:
                have2 = data[pos:pos + ln]
            pos += ln
        elif wt == 5:
            pos += 4
            if pos > end:
                return None
        elif wt == 1:
            pos += 8
            if pos > end:
                return None
        else:
            return None
    if have1 is None or have2 is None:
        return None
    if not (40 <= len(have1) <= 80 and 30 <= len(have2) <= 64):
        return None
    if sum(1 for b in have2 if 32 <= b < 127) < len(have2) * 4 // 5:
        return None
    return (len(have1), len(have2))


def auth_token_shape(data):
    """Wire walk for AuthTokenReply{auth_token=1, error=3}: field 1 = mostly
    printable string 100-260B and NO field 2 (excludes LoginSession, which
    always carries session=2). Returns token length or None."""
    pos, end = 0, len(data)
    if end > 400:
        return None
    have1 = None
    while pos < end:
        b0 = data[pos]
        pos += 1
        fn, wt = b0 >> 3, b0 & 7
        if fn == 0:
            return None
        if wt == 0:
            while pos < end and data[pos] & 0x80:
                pos += 1
            pos += 1
            if pos > end:
                return None
        elif wt == 2:
            ln, sh = 0, 0
            while True:
                if pos >= end:
                    return None
                bb = data[pos]
                pos += 1
                ln |= (bb & 0x7f) << sh
                if not bb & 0x80:
                    break
                sh += 7
                if sh > 63:
                    return None
            if pos + ln > end:
                return None
            if fn == 1 and have1 is None:
                have1 = data[pos:pos + ln]
            elif fn == 2:
                return None
            pos += ln
        elif wt == 5:
            pos += 4
            if pos > end:
                return None
        elif wt == 1:
            pos += 8
            if pos > end:
                return None
        else:
            return None
    if have1 is None or not (100 <= len(have1) <= 260):
        return None
    if sum(1 for b in have1 if 32 <= b < 127) < len(have1) * 4 // 5:
        return None
    return len(have1)


def framing_method(data):
    if not data:
        return None
    n = data[0]
    if n == 0 or 1 + n > len(data):
        return None
    name = data[1:1 + n]
    if all(32 <= b < 127 for b in name):
        return name.decode("ascii")
    return None


def md5_of(path):
    h = hashlib.md5()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


if gdb is not None:

    def read_mem(addr, n):
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
    STATE = {}
    SEQ = [0]
    PARSE_SAVED = [0]
    pending_sendtraps = []
    pending_reqpath = []
    SENDTRAP_DELAY = float(os.environ.get("MYTS_SEND_DELAY", "60"))

    def open_sendtraps():
        n = 0
        for func, bp in pending_sendtraps + pending_reqpath:
            try:
                bp.enabled = True
                n += 1
            except gdb.error as e:
                log("enable LATE %s failed: %s" % (func, e))
        log("LATE open: %d enabled (gated by %s)" % (n, SEND_GATE))

    BODY_CANDIDATES = ("rdi", "rsi", "rdx", "rcx", "r8", "r9")

    def probe_regs(tag):
        """Decode every arg reg as string/vector; return a summary line and
        the most interesting buffer (framed > json > largest)."""
        parts, best, best_kind = [], None, None
        for rn in BODY_CANDIDATES:
            v = reg(rn)
            s = decode_string(read_mem, v)
            vec = decode_vector(read_mem, v)
            fib = None
            if s is not None and vec is not None:
                fib = s if len(s) >= len(vec) else vec
            elif s is not None:
                fib = s
            elif vec is not None:
                fib = vec
            if fib is None:
                parts.append("%s=0x%x:?" % (rn, v))
                continue
            m = framing_method(fib)
            kind = "framed:%s" % m if m else ("json" if looks_like_json(fib) else "raw")
            parts.append("%s=0x%x:%dB:%s" % (rn, v, len(fib), kind))
            if best is None or (m is not None) or (
                    best_kind == "raw" and kind in ("json",) or
                    (best_kind == kind and len(fib) > len(best))):
                best, best_kind = fib, (("framed" if m else kind))
        return " | ".join(parts), best, best_kind

    class ReqBreakpoint(gdb.Breakpoint):
        def stop(self):
            url_b = decode_string(read_mem, reg("rsi"))
            if not looks_like_url(url_b):
                log("REQ skipped: rsi=0x%x not a plausible URL" % reg("rsi"))
                return False
            url = url_b.decode("ascii")
            host, path = split_url(url)
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
            if body is None:
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
            return False

    class RetBreakpoint(gdb.Breakpoint):
        def stop(self):
            return False

    class ParseBreakpoint(gdb.Breakpoint):
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

    class HandlerBreakpoint(gdb.Breakpoint):
        """Beast JSON-response handler hit: dump arg regs, save best buffer."""

        def stop(self):
            summary, best, kind = probe_regs("H")
            SEQ[0] += 1
            seq = SEQ[0]
            if best:
                write_blob("%s-%03d-HANDLER-%s.bin" % (RUN, seq, kind or "raw"), best)
            log("HANDLER @%s thread=%d %s best=%s %dB"
                % (self.tag, tid(), summary, kind, len(best) if best else 0))
            return False

    class ReqPathBreakpoint(gdb.Breakpoint):
        """Request-path entry hit (SSL writer / state machine): same generic
        probe — the plaintext HTTP request (headers + JSON/framed body)
        passes here as a caller buffer before encryption. Metadata only."""

        def stop(self):
            summary, best, kind = probe_regs("R")
            SEQ[0] += 1
            seq = SEQ[0]
            if best:
                write_blob("%s-%03d-REQPATH-%s.bin" % (RUN, seq, kind or "raw"), best)
            log("REQPATH @%s thread=%d %s best=%s %dB"
                % (self.tag, tid(), summary, kind, len(best) if best else 0))
            return False

    import hashlib as _hl

    def obj_walk(tag, this):
        """Dump [this-0x40, this+0x340) raw to .bin; log only offsets,
        lengths and short hashes (never content) for every qword that
        decodes as a string/vector. Returns the saved path or None."""
        SEQ[0] += 1
        seq = SEQ[0]
        raw = read_mem(this - 0x40, 0x380)
        if raw is None:
            log("%s thread=%d this=0x%x unreadable" % (tag, tid(), this))
            return None
        path = write_blob("%s-%03d-obj.bin" % (RUN, seq), raw)
        found = []
        for off in range(0, 0x340, 8):
            q = int.from_bytes(raw[0x40 + off:0x48 + off], "little")
            if q < 0x1000:
                continue
            for kind, s in (("str", decode_string(read_mem, q)),
                            ("vec", decode_vector(read_mem, q))):
                if s is not None and 4 <= len(s) <= 4096:
                    found.append("obj+0x%x:%s:%dB#%s"
                                 % (off, kind, len(s),
                                    _hl.sha256(s).hexdigest()[:8]))
                    break
            if len(found) >= 40:
                break
        stack = read_mem(reg("rsp"), 0x200)
        if stack is not None:
            write_blob("%s-%03d-stack.bin" % (RUN, seq), stack)
        log("%s #%03d thread=%d this=0x%x -> %s | %s"
            % (tag, seq, tid(), this, os.path.basename(path),
               " ".join(found) if found else "no-strings"))
        return path

    class DispatchEntryBreakpoint(gdb.Breakpoint):
        """Beast auth-reply dispatcher ENTRY (FUN_01d45e10): dump the
        handler object (request context lives here) + regs."""

        def stop(self):
            regs = " ".join("%s=0x%x" % (rn, reg(rn)) for rn in BODY_CANDIDATES)
            log("DISPATCH-ENTRY thread=%d %s" % (tid(), regs))
            obj_walk("DISPATCH-OBJ", reg("rdi"))
            return False

    class DispatchParseBreakpoint(gdb.Breakpoint):
        """Dispatcher post-parse point (0x1d460b0, return addr of the reply
        parse call): same object dump, reply already parsed."""

        def stop(self):
            obj_walk("DISPATCH-PARSE", reg("rdi"))
            return False

    SEND_GATE = "/tmp/myts-sendgate"
    SEND_SAVED = [0]
    SEND_CAP = 5000
    SEND_CEF_SAVED = [0]
    SEND_CEF_CAP = 300
    SEND_NOISE = ("libpulse", "libasound", "hotkey_helper",
                  "0x000055555688ef38")

    class SendTrapBreakpoint(gdb.Breakpoint):
        """libc send-family/write hit: gated by SEND_GATE file. bt first:
        audio/hotkey frames dropped uncounted; libcef frames go to a
        separate 300-slot CEF-SEND log (attributes browser-process Chromium
        traffic without drowning the native log); the rest is the native
        sender path. Metadata only."""

        def stop(self):
            if not os.path.exists(SEND_GATE):
                return False
            try:
                bt = gdb.execute("bt 25", to_string=True)
            except gdb.error as e:
                bt = "<bt failed: %s>" % e
            for mark in SEND_NOISE:
                if mark in bt:
                    return False
            fd, length = reg("rdi"), reg("rdx")
            if "libcef.so" in bt:
                if tid() == 1 and length in (1, 112, 16383, 16384, 16448):
                    return False  # main-thread CEF IPC/shm chatter, uncounted
                if SEND_CEF_SAVED[0] >= SEND_CEF_CAP:
                    return False
                SEND_CEF_SAVED[0] += 1
                log("CEF-SEND #%03d thread=%d %s fd=%d len=%d\n%s"
                    % (SEND_CEF_SAVED[0], tid(), self.tag, fd, length, bt))
                return False
            if SEND_SAVED[0] >= SEND_CAP:
                return False
            SEND_SAVED[0] += 1
            log("SEND #%03d thread=%d %s fd=%d len=%d\n%s"
                % (SEND_SAVED[0], tid(), self.tag, fd, length, bt))
            return False

    class ParseEntryBreakpoint(gdb.Breakpoint):
        """ParseFromString ENTRY (all protobuf parses, any stack): save every
        plausible-size buffer for the offline LoginSession hunt, and try the
        match inline — on a hit, log a backtrace to nail the Beast reply
        path. Metadata only in the log, never field values."""

        def stop(self):
            length, data_p = reg("rdx"), reg("rsi")
            if not (64 <= length <= 16384):
                return False
            data = read_mem(data_p, length)
            if data is None:
                return False
            if PARSE_SAVED[0] >= 5000:
                return False
            PARSE_SAVED[0] += 1
            SEQ[0] += 1
            seq = SEQ[0]
            write_blob("%s-%03d-parse-%d.bin" % (RUN, seq, length), data)
            shape = login_session_shape(data)
            if shape is not None:
                write_blob("%s-%03d-LOGIN-REPLY.bin" % (RUN, seq), data)
                try:
                    bt = gdb.execute("bt 25", to_string=True)
                except gdb.error as e:
                    bt = "<bt failed: %s>" % e
                log("LOGIN-REPLY #%03d thread=%d len=%d key_len=%d session_len=%d\n%s"
                    % (seq, tid(), length, shape[0], shape[1], bt))
                return False
            toklen = auth_token_shape(data)
            if toklen is not None:
                write_blob("%s-%03d-AUTH-REPLY.bin" % (RUN, seq), data)
                try:
                    bt = gdb.execute("bt 25", to_string=True)
                except gdb.error as e:
                    bt = "<bt failed: %s>" % e
                log("AUTH-REPLY #%03d thread=%d len=%d token_len=%d\n%s"
                    % (seq, tid(), length, toklen, bt))
            return False

    def load_base():
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
        try:
            bp = ParseEntryBreakpoint("*" + hex(base + OFF_PARSE_ENTRY))
            bp.silent = True
            log("armed PARSE-ENTRY at 0x%x (base 0x%x + 0x%x)"
                % (base + OFF_PARSE_ENTRY, base, OFF_PARSE_ENTRY))
        except gdb.error as e:
            log("skip PARSE-ENTRY: %s" % e)
        for cls, off, tag in (
            (DispatchEntryBreakpoint, OFF_DISPATCH_ENTRY, "DISPATCH-ENTRY"),
            (DispatchParseBreakpoint, OFF_DISPATCH_PARSE, "DISPATCH-PARSE"),
        ):
            try:
                bp = cls("*" + hex(base + off))
            except gdb.error as e:
                log("skip %s: %s" % (tag, e))
                continue
            bp.silent = True
            log("armed %s at 0x%x (base 0x%x + 0x%x)" % (tag, base + off, base, off))
        for off in OFF_REQPATH:
            try:
                bp = ReqPathBreakpoint("*" + hex(base + off))
                pending_reqpath.append(("REQPATH+0x%x" % off, bp))
            except gdb.error as e:
                log("skip REQPATH +0x%x: %s" % (off, e))
                continue
            bp.silent = True
            bp.tag = "0x%x" % off
            bp.enabled = False
            log("planted REQPATH at 0x%x (disabled, opens late)" % (base + off))
        for func in ("send", "sendto", "sendmsg", "sendmmsg", "write", "writev"):
            try:
                bp = SendTrapBreakpoint(func)
                pending_sendtraps.append((func, bp))
            except gdb.error as e:
                log("skip SENDTRAP %s: %s" % (func, e))
                continue
            bp.silent = True
            bp.tag = func
            bp.enabled = False
            log("planted SENDTRAP %s (disabled, opens with gate)" % func)
        for off in OFF_HANDLERS:
            try:
                bp = HandlerBreakpoint("*" + hex(base + off))
            except gdb.error as e:
                log("skip HANDLER +0x%x: %s" % (off, e))
                continue
            bp.silent = True
            bp.tag = "0x%x" % off
            log("armed HANDLER at 0x%x (base 0x%x + 0x%x)" % (base + off, base, off))

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

        gdb.execute("starti")

        def on_stop(event):
            try:
                sig = getattr(event, "stop_signal", None)
            except Exception:
                sig = None
            if sig != "SIGABRT":
                return
            try:
                out = gdb.execute("thread apply all bt 6", to_string=True)
            except gdb.error as e:
                out = "<bt failed: %s>" % e
            try:
                with open(os.path.join(OUT_DIR, RUN + "-abort-bt.log"), "w") as fh:
                    fh.write(out)
            except OSError:
                pass
            log("SIGABRT: wrote abort-bt.log")

        try:
            gdb.events.stop.connect(on_stop)
        except (gdb.error, AttributeError) as e:
            log("stop hook unavailable: %s" % e)
        base = load_base()
        if base is None:
            raise gdb.error("could not find load base for %s" % BINARY)
        log("run=%s base=0x%x pid=%s" % (RUN, base, gdb.selected_inferior().pid))
        install(base)
        import threading as _th

        def _delayed_open():
            import time as _t
            _t.sleep(SENDTRAP_DELAY)
            try:
                gdb.post_event(open_sendtraps)
            except (gdb.error, AttributeError) as e:
                log("delayed open failed: %s" % e)

        log("SENDTRAP opens in %.0fs (startup storm guard)" % SENDTRAP_DELAY)
        _th.Thread(target=_delayed_open, daemon=True).start()
        gdb.execute("continue")

    main()
