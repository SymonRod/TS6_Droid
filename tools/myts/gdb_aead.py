"""gdb script: capture myTeamSpeak item crypto at the AEAD funnel (run9).

Why: run8 proved the lower layers are dead ends for sync items --
  - the libtomcrypt EAX symbols (eax_decrypt_verify_memory / eax_init /
    eax_decrypt) are called from exactly one static site each, all in the
    tsproto voice/command packet path (caller 0x1ee8d2f / 0x1efc517). A
    full .text scan for direct `call` instructions confirms it: the item
    path never reaches them (run8: 0 gated EAX hits out of ~580).
  - ENC-DEC (0x1CEE970) is the *login* unwrap: its inputs parse as
    `Auth_Token_Package`, not item_blobs. It fires at first login only
    (renewal logins skip it).
  - ITEM (0x1CD3DF0) fired once at startup with init-sized args, never with
    item data -- the pull decrypts after re-login (bookmarks visible, zero
    hits) bypass it.

The funnel both paths share is the teamcrypto AEAD open `0x2166560`
(called from ITEM twice, from ENC once, from the tsproto OutPacket glue 4
times, and from 1636 static call sites overall). Static basis: pinned build
md5 8234f961..., PIE link vaddrs, add the load base.

Strategy: break at 0x2166560. At entry, probe rdi/rsi/rdx/rcx/r8/r9 and the
first stack slots as libc++ std::string* and dump whatever decodes (the
item_blob ~260-360 B, key 16-64 B and iv show up as strings); at return,
dump the output string via the saved rdi. Always log a base-relative
backtrace. Full buffer dumps happen only when the stack contains a frame
in the sync-manager range [0x1CC0000, 0x1D00000) (covers ITEM, ENC and the
pull/push handler that the ENC backtraces implicate: 0x1ce73d6...,
0x1ccb173); other callers (voice, chat, ...) are log-only.

Outputs (git-ignored, next to the capture log):

  <run>-aead-NNN.a0..a5.bin + .s0..s7.bin   decoded string args (gated only)
  <run>-aead-NNN.out.bin                    output string at return (gated)
  <run>-item-NNN.blob/.plain.bin            ENC-DEC login unwrap (as run8)
The log records sizes / threads / gate flag / backtrace PCs only -- never
key/iv/pt bytes, per the research-plan secrets rule.

  MYTS_RUN=run9 gdb -batch -nx -x tools/myts/gdb_aead.py \\
      --args /opt/teamspeak/TeamSpeak
  MYTS_DRY=1 gdb -batch -nx -x tools/myts/gdb_aead.py   # checks, no run
"""

import hashlib
import os
import struct
import sys
import time

try:
    import gdb
except ImportError:  # py_compile / self-test outside gdb
    gdb = None

BINARY = "/opt/teamspeak/TeamSpeak"
BINARY_MD5 = "8234f961015da34f1387fa735a7443b0"

# The teamcrypto AEAD open both item paths share (link vaddr + load base).
OFF_AEAD = 0x2166560

# High-level entries (kept from gdb_item.py for context).
OFF_ENC = 0x1CEE970
OFF_ENC_END = 0x1CEEDBE
OFF_ITEM = 0x1CD3DF0
OFF_ITEM_END = 0x1CD4D44

# Sync-manager + RPC code range for the stack gate (pull decrypt path is
# RPC 0x1df -> sync 0x1ca -> AEAD, missed by the first run9 gate; the ENC
# login chain sits at 0x1cc/0x1ce; tsproto voice glue lives at 0x1e2+).
SYNC_LO = 0x1C80000
SYNC_HI = 0x1E00000

MAX_BLOB = 1 << 20
BT_DEPTH = 8
N_STACK_SLOTS = 8  # stack arg slots probed as string pointers

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.environ.get("MYTS_OUT", os.path.join(ROOT, "captures", "myts"))
RUN = os.environ.get("MYTS_RUN", "") or "run"


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


def md5_of(path):
    h = hashlib.md5()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


if gdb is not None:

    BASE = [0]

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

    LOG_PATH = os.path.join(OUT_DIR, RUN + "-aead.log")

    def log(msg):
        line = "[%.3f] %s" % (time.time(), msg)
        print(line, file=sys.stderr)
        try:
            with open(LOG_PATH, "a") as fh:
                fh.write(line + "\n")
        except OSError:
            pass

    def dump(seq, kind, data, prefix="aead"):
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

    def gated(pcs):
        base = BASE[0]
        for p in pcs:
            off = int(p, 16)
            if SYNC_LO <= off < SYNC_HI:
                return True
        return False

    class AeadFinish(gdb.FinishBreakpoint):
        """At AEAD return, decode the output std::string via saved rdi."""

        def __init__(self, frame, seq, out_ptr):
            super(AeadFinish, self).__init__(frame, internal=True)
            self.silent = True
            self.seq = seq
            self.out_ptr = out_ptr

        def stop(self):
            s = decode_string(read_mem, self.out_ptr)
            n = dump(self.seq, "out", s) if s is not None else -1
            try:
                rax = int(gdb.newest_frame().read_register("rax")) & 0xFFFFFFFFFFFFFFFF
            except (gdb.error, ValueError):
                rax = -1
            log("  #%03d out=%dB rax=0x%x" % (self.seq, n, rax))
            return False

        def out_of_scope(self):
            log("  #%03d out lost (frame out of scope)" % self.seq)

    class AeadBreakpoint(gdb.Breakpoint):
        """AEAD funnel entry: probe regs + stack slots as strings; dump gated."""

        def stop(self):
            seq = next_seq()
            bt = backtrace()
            gate = gated(bt)
            regs = [(n, reg(n)) for n in ("rdi", "rsi", "rdx", "rcx", "r8", "r9")]
            slots = [(i, stack_q(0x8 * i)) for i in range(N_STACK_SLOTS)]
            found = []
            for tag, ptr in ([("a%d" % i, p) for i, (_, p) in enumerate(regs)] +
                             [("s%d" % i, p) for i, (_, p) in enumerate(slots)]):
                s = decode_string(read_mem, ptr)
                if s is not None:
                    found.append((tag, len(s)))
                    if gate:
                        dump(seq, tag, s)
            log("AEAD #%03d thread=%d gate=%d strs=%s bt=%s"
                % (seq, tid(), gate, ",".join("%s=%dB" % f for f in found),
                   ",".join(bt[:6])))
            if gate:
                try:
                    AeadFinish(gdb.newest_frame(), seq, regs[0][1])
                except (gdb.error, ValueError) as e:
                    log("  #%03d finish arm failed: %s" % (seq, e))
            return False

    class StringFinish(gdb.FinishBreakpoint):
        """At ENC-DEC return, decode the output std::string at saved rdi."""

        def __init__(self, frame, seq, out_ptr):
            super(StringFinish, self).__init__(frame, internal=True)
            self.silent = True
            self.seq = seq
            self.out_ptr = out_ptr

        def stop(self):
            s = decode_string(read_mem, self.out_ptr)
            n = dump(self.seq, "plain", s, prefix="item") if s is not None else -1
            log("  #%03d plain=%dB" % (self.seq, n))
            return False

        def out_of_scope(self):
            log("  #%03d plain lost (frame out of scope)" % self.seq)

    class EncBreakpoint(gdb.Breakpoint):
        """ENC-DEC entry (login unwrap): dump rdx input, arm finish."""

        def stop(self):
            seq = next_seq()
            out_p = reg("rdi")
            blob = decode_string(read_mem, reg("rdx"))
            nb = dump(seq, "blob", blob, prefix="item")
            log("ENC #%03d thread=%d blob=%dB out=0x%x bt=%s"
                % (seq, tid(), nb, out_p, ",".join(backtrace()[:6])))
            if out_p:
                try:
                    StringFinish(gdb.newest_frame(), seq, out_p)
                except (gdb.error, ValueError) as e:
                    log("  #%03d finish arm failed: %s" % (seq, e))
            return False

    class ItemBreakpoint(gdb.Breakpoint):
        """ITEM entry: object args -- probes + backtrace only."""

        def stop(self):
            seq = next_seq()
            probes = []
            for rn in ("rdi", "rsi", "rdx", "rcx"):
                s = decode_string(read_mem, reg(rn))
                probes.append("%s=%s" % (rn, ("%dB" % len(s)) if s is not None else "?"))
            log("ITEM #%03d thread=%d %s bt=%s"
                % (seq, tid(), " ".join(probes), ",".join(backtrace()[:6])))
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
