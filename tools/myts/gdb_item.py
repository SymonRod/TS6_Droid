"""gdb script: capture myTeamSpeak item crypto via the high-level path (run8).

Why a new script: run7 hooked the libtomcrypt EAX primitives directly and
caught 576 decryptions, but offline analysis showed the plaintexts are TS
command-channel traffic (``notifyclientleftview ...``, ``error id=0 msg=ok``)
-- the EAX primitive is shared with tsproto voice/command crypto. None of the
run7 ciphertexts matches the three run6 ``item_blob``s (313/262/357 B), and no
run7 plaintext parses as ``Item_Data``. So the primitive-level hook cannot
isolate the sync item path.

Static basis (pinned build md5 8234f961..., PIE link vaddrs, add load base;
see objdump notes in the run8 design):

  - ``0x1CEE970`` ENC-DEC (Encryption.cpp decrypt+verify): ``(rdi=out
    std::string*, rsi=key-provider object, rdx=in std::string*)``. The input
    string is the encrypted blob; the provider's ``+0x48`` vcall returns a
    64-byte string (size checked against ``0x40``); the ``0x3e3e32``
    (``plain_hash.size() == sha512_size``) assert path lives here.
  - ``0x1CD3DF0`` ITEM (Item_Manager.cpp item crypto fn, ``!salt.empty()``):
    ``rdi=this`` (+0x1f0/+0x2d0 members), ``rsi``/``rdx`` are interface
    objects (vcalls +0x10/+0x18/+0x28) -- NOT plain strings, so its entry
    args are log-only + backtrace.
  - Both call the shared AEAD wrapper ``0x2166560`` (ENC once, ITEM twice),
    which is the funnel to the EAX primitive.

Strategy: hook the high-level entries AND the EAX primitives, but only dump
EAX buffers when an ITEM/ENC frame is on the stack (stack-gated capture).
Every EAX hit always logs a short base-relative backtrace, so the log alone
answers "who calls EAX" even for ungated (tsproto) hits.

Outputs (git-ignored, next to the capture log):

  <run>-item-NNN.blob.bin    ENC-DEC input string (encrypted blob candidate)
  <run>-item-NNN.plain.bin   ENC-DEC output string at return (Item_Data candidate)
  <run>-dec-NNN.key/iv/ct/tag/pt.bin   EAX buffers, ONLY when gated
The log records sizes / threads / gate flag / backtrace PCs only -- never
key/iv/pt bytes, per the research-plan secrets rule.

  MYTS_RUN=run8 gdb -batch -nx -x tools/myts/gdb_item.py \\
      --args /opt/teamspeak/TeamSpeak
  MYTS_DRY=1 gdb -batch -nx -x tools/myts/gdb_item.py   # checks, no run
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

# High-level item-crypto entries (link vaddrs; add PIE load base at runtime).
OFF_ENC = 0x1CEE970       # Encryption.cpp decrypt+verify fn
OFF_ENC_END = 0x1CEEDBE   #  .. function extent (for the stack gate)
OFF_ITEM = 0x1CD3DF0      # Item_Manager.cpp item crypto fn
OFF_ITEM_END = 0x1CD4D44  #  .. function extent (for the stack gate)

# libtomcrypt EAX entries (same as gdb_decrypt.py).
OFF_EAX_DVM = 0x214A070   # eax_decrypt_verify_memory (one-shot)
OFF_EAX_DEC = 0x214A270   # eax_decrypt (streaming)
OFF_EAX_INIT = 0x214A670  # eax_init (key/iv for the streaming path)

MAX_KEY = 64
MAX_IV = 64
MAX_BLOB = 1 << 20
BT_DEPTH = 8  # backtrace frames logged per hit (PCs only, base-relative)

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

    BASE = [0]  # PIE load base, set after starti

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

    LOG_PATH = os.path.join(OUT_DIR, RUN + "-item.log")

    def log(msg):
        line = "[%.3f] %s" % (time.time(), msg)
        print(line, file=sys.stderr)
        try:
            with open(LOG_PATH, "a") as fh:
                fh.write(line + "\n")
        except OSError:
            pass

    def dump(seq, kind, data, prefix="dec"):
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
        """Base-relative PCs of the current stack, oldest-last. PC-only."""
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
        """True if any stack PC falls inside the ITEM or ENC function ranges."""
        base = BASE[0]
        for p in pcs:
            pc = int(p, 16) + base
            if OFF_ENC <= pc - base < OFF_ENC_END or OFF_ITEM <= pc - base < OFF_ITEM_END:
                return True
        return False

    class StringFinish(gdb.FinishBreakpoint):
        """At ENC-DEC return, decode the output std::string at the saved rdi."""

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
        """ENC-DEC entry: dump the rdx input string, arm finish for output."""

        def stop(self):
            seq = next_seq()
            out_p = reg("rdi")
            blob = decode_string(read_mem, reg("rdx"))
            nb = dump(seq, "blob", blob, prefix="item")
            bt = backtrace()
            log("ENC #%03d thread=%d blob=%dB out=0x%x bt=%s"
                % (seq, tid(), nb, out_p, ",".join(bt[:6])))
            if out_p:
                try:
                    StringFinish(gdb.newest_frame(), seq, out_p)
                except (gdb.error, ValueError) as e:
                    log("  #%03d finish arm failed: %s" % (seq, e))
            return False

    class ItemBreakpoint(gdb.Breakpoint):
        """ITEM entry: args are objects, not strings -- probes + backtrace only."""

        def stop(self):
            seq = next_seq()
            probes = []
            for rn in ("rdi", "rsi", "rdx", "rcx"):
                s = decode_string(read_mem, reg(rn))
                probes.append("%s=%s" % (rn, ("%dB" % len(s)) if s is not None else "?"))
            log("ITEM #%03d thread=%d %s bt=%s"
                % (seq, tid(), " ".join(probes), ",".join(backtrace()[:6])))
            return False

    class GatedFinish(gdb.FinishBreakpoint):
        """Fire when a gated one-shot AEAD frame returns; dump pt + stat."""

        def __init__(self, frame, seq, pt_ptr, length, stat_ptr):
            super(GatedFinish, self).__init__(frame, internal=True)
            self.silent = True
            self.seq = seq
            self.pt_ptr = pt_ptr
            self.length = length
            self.stat_ptr = stat_ptr

        def stop(self):
            n = dump(self.seq, "pt", read_mem(self.pt_ptr, self.length))
            stat = None
            if self.stat_ptr:
                raw = read_mem(self.stat_ptr, 4)
                stat = struct.unpack("<i", raw)[0] if raw else None
            log("  #%03d pt=%dB stat=%s" % (self.seq, n, stat))
            return False

        def out_of_scope(self):
            log("  #%03d pt lost (frame out of scope)" % self.seq)

    def maybe_dump(seq, kind, data):
        """Dump helper used only on the gated path."""
        return dump(seq, kind, data)

    class DvmBreakpoint(gdb.Breakpoint):
        """eax_decrypt_verify_memory entry: always log + backtrace; dump only
        when an ITEM/ENC frame is on the stack."""

        def stop(self):
            seq = next_seq()
            bt = backtrace()
            gate = gated(bt)
            cipher = reg("rdi") & 0xFFFFFFFF
            key_p, key_l = reg("rsi"), reg("rdx")
            iv_p, iv_l = reg("rcx"), reg("r8")
            ct_p, ct_l = stack_q(0x10), stack_q(0x18)
            pt_p = stack_q(0x20)
            tag_p, tag_l = stack_q(0x28), stack_q(0x30)
            stat_p = stack_q(0x38)
            if gate:
                nk = maybe_dump(seq, "key", read_mem(key_p, min(key_l, MAX_KEY)))
                ni = maybe_dump(seq, "iv", read_mem(iv_p, min(iv_l, MAX_IV)))
                nc = maybe_dump(seq, "ct", read_mem(ct_p, min(ct_l, MAX_BLOB)))
                nt = maybe_dump(seq, "tag", read_mem(tag_p, min(tag_l, MAX_IV)))
            else:
                nk, ni = min(key_l, MAX_KEY), min(iv_l, MAX_IV)
                nc = min(ct_l, MAX_BLOB)
                nt = min(tag_l, MAX_IV)
            log("DVM #%03d thread=%d gate=%d cipher=%d key=%dB iv=%dB ct=%dB "
                "tag=%dB bt=%s" % (seq, tid(), gate, cipher, nk, ni, nc, nt,
                                   ",".join(bt[:4])))
            if gate and pt_p and 0 < ct_l <= MAX_BLOB:
                try:
                    GatedFinish(gdb.newest_frame(), seq, pt_p, ct_l, stat_p)
                except (gdb.error, ValueError) as e:
                    log("  #%03d finish arm failed: %s" % (seq, e))
            return False

    class InitBreakpoint(gdb.Breakpoint):
        """eax_init entry: streaming key/iv; dump only when gated."""

        def stop(self):
            seq = next_seq()
            bt = backtrace()
            gate = gated(bt)
            key_p, key_l = reg("rdx"), reg("rcx")
            iv_p, iv_l = reg("r8"), reg("r9")
            state = reg("rdi")
            if gate:
                nk = maybe_dump(seq, "key", read_mem(key_p, min(key_l, MAX_KEY)))
                ni = maybe_dump(seq, "iv", read_mem(iv_p, min(iv_l, MAX_IV)))
                STATE_KEYS[state] = seq
            else:
                nk, ni = min(key_l, MAX_KEY), min(iv_l, MAX_IV)
            log("INIT #%03d thread=%d gate=%d state=0x%x key=%dB iv=%dB bt=%s"
                % (seq, tid(), gate, state, nk, ni, ",".join(bt[:4])))
            return False

    class DecBreakpoint(gdb.Breakpoint):
        """eax_decrypt entry (streaming): dump only when gated."""

        def stop(self):
            seq = next_seq()
            bt = backtrace()
            gate = gated(bt)
            state = reg("rdi")
            ct_p, pt_p, length = reg("rsi"), reg("rdx"), reg("rcx")
            if gate:
                nc = maybe_dump(seq, "ct", read_mem(ct_p, min(length, MAX_BLOB)))
            else:
                nc = min(length, MAX_BLOB)
            log("DEC #%03d thread=%d gate=%d state=0x%x init=#%s ct=%dB bt=%s"
                % (seq, tid(), gate, state, STATE_KEYS.get(state, "?"), nc,
                   ",".join(bt[:4])))
            if gate and pt_p and 0 < length <= MAX_BLOB:
                try:
                    GatedFinish(gdb.newest_frame(), seq, pt_p, length, 0)
                except (gdb.error, ValueError) as e:
                    log("  #%03d finish arm failed: %s" % (seq, e))
            return False

    STATE_KEYS = {}  # eax_state ptr -> init seq (streaming correlation)

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
        for cls, off, tag in ((DvmBreakpoint, OFF_EAX_DVM, "DVM"),
                              (InitBreakpoint, OFF_EAX_INIT, "INIT"),
                              (DecBreakpoint, OFF_EAX_DEC, "DEC")):
            bp = cls("*" + hex(base + off))
            bp.silent = True
            log("armed %s at 0x%x" % (tag, base + off))
        for cls, off, tag in ((EncBreakpoint, OFF_ENC, "ENC"),
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
