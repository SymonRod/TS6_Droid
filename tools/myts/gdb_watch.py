"""gdb script: find the sync item crypt via read-watchpoints on the key (run13).

Why: run12 proved the push encrypts with ZERO calls to the AEAD funnel
0x2166560 (or any hooked EAX symbol) -- versions in settings.db advanced
at the toggle second, yet no AEAD fired in a 5-minute window. So the item
crypt is either inlined or uses an unhooked primitive. Either way it must
READ the unwrapped password.

Strategy: hook ENC-DEC (the login/password unwrap, reliably fires on every
bookmark toggle: 2-4 Auth_Token_Package unwraps). At return, dump the
output string AND plant a hardware read-watchpoint on its first word.
When the item encrypt/KDF reads the key, the watchpoint fires: log the
base-relative backtrace + probe the string args at that frame. x86 has 4
debug registers, so only the 4 most recent unwrap buffers are watched
(older watchpoints are auto-disabled).

Static basis: pinned build md5 8234f961..., PIE link vaddrs + load base.
ENC-DEC 0x1CEE970 (rdi=out string*, rdx=in string*); AEAD funnel
0x2166560 kept for context; sync gate [0x1C80000, 0x1E00000) as in run12.

Outputs: <run>-item-NNN.blob/.plain.bin (unwraps, as before). The log
records sizes / threads / backtraces only -- never key/iv/pt bytes.

  MYTS_RUN=run13 gdb -batch -nx -x tools/myts/gdb_watch.py \\
      --args /opt/teamspeak/TeamSpeak
  MYTS_DRY=1 gdb -batch -nx -x tools/myts/gdb_watch.py   # checks, no run
"""

import hashlib
import os
import struct
import sys
import time

try:
    import gdb
except ImportError:
    gdb = None

BINARY = "/opt/teamspeak/TeamSpeak"
BINARY_MD5 = "8234f961015da34f1387fa735a7443b0"

OFF_AEAD = 0x2166560
OFF_ENC = 0x1CEE970
OFF_ITEM = 0x1CD3DF0
OFF_ITEM_END = 0x1CD4D44

SYNC_LO = 0x1C80000
SYNC_HI = 0x1E00000

MAX_BLOB = 1 << 20
BT_DEPTH = 8
N_STACK_SLOTS = 8
MAX_WATCHES = 4      # x86 debug registers
MAX_WATCH_HITS = 200  # tripwire cap: disable watches after this many hits

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.environ.get("MYTS_OUT", os.path.join(ROOT, "captures", "myts"))
RUN = os.environ.get("MYTS_RUN", "") or "run"


def decode_string(read, ptr):
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


def md5_of(path):
    h = hashlib.md5()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


if gdb is not None:

    BASE = [0]
    WATCHES = []  # live KeyWatch objects, oldest first
    WATCH_HITS = [0]

    def read_mem(addr, n):
        if n <= 0 or addr < 0x1000:
            return b"" if n == 0 else None
        try:
            return bytes(gdb.selected_inferior().read_memory(addr, n))
        except (gdb.MemoryError, gdb.error, OverflowError, ValueError):
            return None

    def reg(name):
        try:
            return int(gdb.newest_frame().read_register(name)) & 0xFFFFFFFFFFFFFFFF
        except (gdb.error, ValueError):
            return 0

    def stack_q(off):
        raw = read_mem(reg("rsp") + off, 8)
        return struct.unpack("<Q", raw)[0] if raw else 0

    def tid():
        t = gdb.selected_thread()
        return t.global_num if t is not None else 0

    LOG_PATH = os.path.join(OUT_DIR, RUN + "-watch.log")

    def log(msg):
        line = "[%.3f] %s" % (time.time(), msg)
        print(line, file=sys.stderr)
        try:
            with open(LOG_PATH, "a") as fh:
                fh.write(line + "\n")
        except OSError:
            pass

    def dump(seq, kind, data, prefix="item"):
        if data is None:
            return -1
        path = os.path.join(OUT_DIR, "%s-%s-%03d.%s.bin" % (RUN, prefix, seq, kind))
        with open(path, "wb") as fh:
            fh.write(data)
        return len(data)

    SEQ = [0]

    def next_seq():
        SEQ[0] += 1
        return SEQ[0]

    def backtrace():
        pcs = []
        try:
            f = gdb.newest_frame()
            for _ in range(BT_DEPTH):
                pc = int(f.pc())
                pcs.append("0x%x" % (pc - BASE[0]) if BASE[0] else "0x%x" % pc)
                f = f.older()
                if f is None:
                    break
        except gdb.error:
            pass
        return pcs

    def string_args():
        """Probe regs + stack slots as std::string*; return [(tag, size)]."""
        found = []
        regs = [reg(n) for n in ("rdi", "rsi", "rdx", "rcx", "r8", "r9")]
        for i, p in enumerate(regs):
            s = decode_string(read_mem, p)
            if s is not None:
                found.append(("a%d" % i, len(s)))
        for i in range(N_STACK_SLOTS):
            s = decode_string(read_mem, stack_q(0x8 * i))
            if s is not None:
                found.append(("s%d" % i, len(s)))
        return found

    class KeyWatch(gdb.Breakpoint):
        """Hardware read-watchpoint on an unwrap output buffer's first word."""

        def __init__(self, addr, seq):
            super(KeyWatch, self).__init__(
                "*(long *)0x%x" % addr, type=gdb.BP_READ_WATCHPOINT,
                internal=True)
            self.silent = True
            self.addr = addr
            self.seq = seq

        def stop(self):
            WATCH_HITS[0] += 1
            n = WATCH_HITS[0]
            bt = backtrace()
            try:
                args = string_args()
            except gdb.error:
                args = []
            log("KEYREAD #%03d hit=%d thread=%d bufseq=#%03d strs=%s bt=%s"
                % (self.seq, n, tid(), self.seq,
                   ",".join("%s=%dB" % a for a in args), ",".join(bt[:6])))
            if n >= MAX_WATCH_HITS:
                for w in WATCHES:
                    try:
                        w.enabled = False
                    except gdb.error:
                        pass
                log("KEYREAD watch cap reached; watches disabled")
            return False

    def plant_watch(addr, seq):
        """Watch the first word of an unwrap buffer; keep max MAX_WATCHES."""
        while len(WATCHES) >= MAX_WATCHES:
            old = WATCHES.pop(0)
            try:
                old.enabled = False
            except gdb.error:
                pass
        try:
            w = KeyWatch(addr, seq)
            WATCHES.append(w)
            log("  #%03d keywatch armed at 0x%x" % (seq, addr))
        except gdb.error as e:
            log("  #%03d keywatch failed: %s" % (seq, e))

    def buf_data_addr(out_ptr):
        """Heap data address of the std::string at out_ptr, or None."""
        raw = read_mem(out_ptr, 24)
        if raw is None:
            return None
        if raw[0] & 1:
            _, size, data = struct.unpack("<QQQ", raw)
            if 0 < size <= MAX_BLOB and data >= 0x1000:
                return data
            return None
        # short form lives inline (stack) -- not watchable, skip
        return None

    class StringFinish(gdb.FinishBreakpoint):
        def __init__(self, frame, seq, out_ptr):
            super(StringFinish, self).__init__(frame, internal=True)
            self.silent = True
            self.seq = seq
            self.out_ptr = out_ptr

        def stop(self):
            s = decode_string(read_mem, self.out_ptr)
            n = dump(self.seq, "plain", s) if s is not None else -1
            log("  #%03d plain=%dB" % (self.seq, n))
            addr = buf_data_addr(self.out_ptr)
            if addr:
                plant_watch(addr, self.seq)
            else:
                log("  #%03d short/inline buffer, not watched" % self.seq)
            return False

        def out_of_scope(self):
            log("  #%03d plain lost (frame out of scope)" % self.seq)

    class EncBreakpoint(gdb.Breakpoint):
        def stop(self):
            seq = next_seq()
            out_p = reg("rdi")
            blob = decode_string(read_mem, reg("rdx"))
            nb = dump(seq, "blob", blob)
            log("ENC #%03d thread=%d blob=%dB out=0x%x bt=%s"
                % (seq, tid(), nb, out_p, ",".join(backtrace()[:6])))
            if out_p:
                try:
                    StringFinish(gdb.newest_frame(), seq, out_p)
                except (gdb.error, ValueError) as e:
                    log("  #%03d finish arm failed: %s" % (seq, e))
            return False

    class ItemBreakpoint(gdb.Breakpoint):
        def stop(self):
            seq = next_seq()
            probes = []
            for rn in ("rdi", "rsi", "rdx", "rcx"):
                s = decode_string(read_mem, reg(rn))
                probes.append("%s=%s" % (rn, ("%dB" % len(s)) if s is not None else "?"))
            log("ITEM #%03d thread=%d %s bt=%s"
                % (seq, tid(), " ".join(probes), ",".join(backtrace()[:6])))
            return False

    class AeadBreakpoint(gdb.Breakpoint):
        def stop(self):
            seq = next_seq()
            bt = backtrace()
            gate = any(SYNC_LO <= int(p, 16) < SYNC_HI for p in bt)
            log("AEAD #%03d thread=%d gate=%d strs=%s bt=%s"
                % (seq, tid(), gate,
                   ",".join("%s=%dB" % a for a in string_args()),
                   ",".join(bt[:6])))
            return False

    def load_base():
        out = gdb.execute("info proc mappings", to_string=True)
        best = None
        for line in out.splitlines():
            cols = line.split()
            if len(cols) >= 5 and cols[-1] == BINARY:
                try:
                    start, off = int(cols[0], 16), int(cols[3], 16)
                except ValueError:
                    continue
                if off == 0 and (best is None or start < best):
                    best = start
        return best

    def install(base):
        for cls, off, tag in ((AeadBreakpoint, OFF_AEAD, "AEAD"),
                              (EncBreakpoint, OFF_ENC, "ENC"),
                              (ItemBreakpoint, OFF_ITEM, "ITEM")):
            bp = cls("*" + hex(base + off))
            bp.silent = True
            log("armed %s at 0x%x" % (tag, base + off))

    def preflight():
        problems = []
        if not os.path.exists(BINARY):
            problems.append("binary missing: %s" % BINARY)
        elif md5_of(BINARY) != BINARY_MD5:
            problems.append("md5 mismatch on %s" % BINARY)
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
        base = load_base()
        if base is None:
            raise gdb.error("could not find load base for %s" % BINARY)
        BASE[0] = base
        log("run=%s base=0x%x pid=%s" % (RUN, base, gdb.selected_inferior().pid))
        install(base)
        gdb.execute("continue")

    main()
