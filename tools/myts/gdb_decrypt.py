"""gdb script: capture myTeamSpeak item AEAD decryptions in-process (task 1D).

Companion to gdb_capture.py. Same model: launch the isolated desktop client
as a child of gdb (kernel.yama.ptrace_scope = 1 forbids attaching later) and
arm non-stopping breakpoints, but here on the teamcrypto/libtomcrypt AEAD
primitives so we read the item key + iv + ciphertext + plaintext at the
moment the client decrypts a synced item_blob (Item_Data).

Static basis (pinned build md5 8234f961…, PIE link vaddrs, add the load base):

  Sync item crypto is teamcrypto/libtomcrypt **EAX-AES** (no teamcrypto GCM /
  ChaCha / Poly1305 is compiled in; the *_GCM strings in the binary are
  OpenSSL/TLS suite names). Anchors:
    - Item_Manager.cpp `Assertion "!salt.empty()"`  -> string 0x33d18e,
      referenced twice inside FUNC 0x1cd3df0..0x1cd4d44 (one item crypto fn).
    - Encryption.cpp `Assertion "plain_hash.size() == …sha512_size"` ->
      string 0x3e3e32, inside FUNC 0x1cee970..0x1ceedbe (decrypt + verify).
  libtomcrypt EAX entries (from .eh_frame FDEs; this build has no endbr64):
    - eax_decrypt_verify_memory  0x214a070   (one-shot AEAD open)
    - eax_decrypt (streaming)    0x214a270
    - eax_init                   0x214a670
    - eax_done                   0x214a320

libtomcrypt ABIs (SysV AMD64, args at function entry):

  int eax_decrypt_verify_memory(int cipher, const u8 *key, ulong keylen,
        const u8 *nonce, ulong noncelen, const u8 *header, ulong headerlen,
        const u8 *ct, ulong ctlen, u8 *pt, const u8 *tag, ulong taglen,
        int *stat);
    edi=cipher  rsi=key  rdx=keylen  rcx=nonce(iv)  r8=noncelen  r9=header
    [rsp+0x08]=headerlen [rsp+0x10]=ct [rsp+0x18]=ctlen [rsp+0x20]=pt
    [rsp+0x28]=tag [rsp+0x30]=taglen [rsp+0x38]=stat        (ptlen == ctlen)

  int eax_init(eax_state *st, int cipher, const u8 *key, ulong keylen,
        const u8 *nonce, ulong noncelen, const u8 *header, ulong headerlen);
    rdi=state esi=cipher rdx=key rcx=keylen r8=nonce(iv) r9=noncelen

  int eax_decrypt(eax_state *st, const u8 *ct, u8 *pt, ulong length);
    rdi=state rsi=ct rdx=pt rcx=length

Outputs (git-ignored, next to the capture log):
  <run>-dec-NNN.key.bin .iv.bin .ct.bin .tag.bin .pt.bin   (one-shot path)
  <run>-dec-NNN.key.bin .iv.bin                            (streaming init)
  <run>-dec-NNN.ct.bin .pt.bin                             (streaming decrypt)
The log records sizes / cipher idx / thread / stat only -- never key/iv/pt
bytes, per the research-plan secrets rule. Correlate ct offline with the
captured run6 item_blob(s) via tools/myts/analyze.py.

  MYTS_RUN=run7 gdb -batch -nx -x tools/myts/gdb_decrypt.py \\
      --args /opt/teamspeak/TeamSpeak
  MYTS_DRY=1 gdb -batch -nx -x tools/myts/gdb_decrypt.py   # checks, no run

Offsets are for the pinned build only; the script refuses anything else.
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

# EAX primitive entries (link vaddrs; add PIE load base at runtime).
OFF_EAX_DVM = 0x214A070   # eax_decrypt_verify_memory (one-shot)
OFF_EAX_DEC = 0x214A270   # eax_decrypt (streaming)
OFF_EAX_INIT = 0x214A670  # eax_init (key/iv for the streaming path)
# High-level markers, log-only (confirm the call path + correlate the blob).
OFF_ENC_DEC = 0x1CEE970   # Encryption.cpp decrypt+verify fn
OFF_ITEM = 0x1CD3DF0      # Item_Manager.cpp item crypto fn (!salt.empty x2)

MAX_KEY = 64          # AES key <= 32; allow slack
MAX_IV = 64
MAX_BLOB = 1 << 20    # an item_blob is a few hundred bytes; cap generously

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.environ.get("MYTS_OUT", os.path.join(ROOT, "captures", "myts"))
RUN = os.environ.get("MYTS_RUN", "") or "run"


# --- libc++ std::string decoding (same layout as gdb_capture.py) ----------

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


# --- everything below needs a live gdb ------------------------------------

if gdb is not None:

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
        """Read an 8-byte stack slot at rsp+off (a call arg at entry)."""
        raw = read_mem(reg("rsp") + off, 8)
        return struct.unpack("<Q", raw)[0] if raw else 0

    def tid():
        t = gdb.selected_thread()
        return t.global_num if t is not None else 0

    LOG_PATH = os.path.join(OUT_DIR, RUN + "-decrypt.log")

    def log(msg):
        line = "[%.3f] %s" % (time.time(), msg)
        print(line, file=sys.stderr)
        try:
            with open(LOG_PATH, "a") as fh:
                fh.write(line + "\n")
        except OSError:
            pass

    def dump(seq, kind, data):
        """Write a captured buffer; return its size. Never logs the bytes."""
        if data is None:
            return -1
        path = os.path.join(OUT_DIR, "%s-dec-%03d.%s.bin" % (RUN, seq, kind))
        with open(path, "wb") as fh:
            fh.write(data)
        return len(data)

    SEQ = [0]

    def next_seq():
        SEQ[0] += 1
        return SEQ[0]

    class NonStopFinish(gdb.FinishBreakpoint):
        """Fire when the current AEAD frame returns, read the plaintext the
        callee just wrote into `pt`, then keep running (never stops)."""

        def __init__(self, frame, seq, pt_ptr, length, stat_ptr):
            super(NonStopFinish, self).__init__(frame, internal=True)
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

    class DvmBreakpoint(gdb.Breakpoint):
        """eax_decrypt_verify_memory entry: capture key/iv/ct/tag, arm finish
        to grab pt (== ctlen bytes) after the call fills it."""

        def stop(self):
            seq = next_seq()
            cipher = reg("rdi") & 0xFFFFFFFF
            key_p, key_l = reg("rsi"), reg("rdx")
            iv_p, iv_l = reg("rcx"), reg("r8")
            ct_p, ct_l = stack_q(0x10), stack_q(0x18)
            pt_p = stack_q(0x20)
            tag_p, tag_l = stack_q(0x28), stack_q(0x30)
            stat_p = stack_q(0x38)
            nk = dump(seq, "key", read_mem(key_p, min(key_l, MAX_KEY)))
            ni = dump(seq, "iv", read_mem(iv_p, min(iv_l, MAX_IV)))
            nc = dump(seq, "ct", read_mem(ct_p, min(ct_l, MAX_BLOB)))
            nt = dump(seq, "tag", read_mem(tag_p, min(tag_l, MAX_IV)))
            log("DVM #%03d thread=%d cipher=%d key=%dB iv=%dB ct=%dB tag=%dB"
                % (seq, tid(), cipher, nk, ni, nc, nt))
            if pt_p and 0 < ct_l <= MAX_BLOB:
                try:
                    NonStopFinish(gdb.newest_frame(), seq, pt_p, ct_l, stat_p)
                except (gdb.error, ValueError) as e:
                    log("  #%03d finish arm failed: %s" % (seq, e))
            return False

    class InitBreakpoint(gdb.Breakpoint):
        """eax_init entry: streaming path key/iv (rdx=key rcx=len r8=iv r9=len)."""

        def stop(self):
            seq = next_seq()
            key_p, key_l = reg("rdx"), reg("rcx")
            iv_p, iv_l = reg("r8"), reg("r9")
            state = reg("rdi")
            nk = dump(seq, "key", read_mem(key_p, min(key_l, MAX_KEY)))
            ni = dump(seq, "iv", read_mem(iv_p, min(iv_l, MAX_IV)))
            STATE_KEYS[state] = seq
            log("INIT #%03d thread=%d state=0x%x key=%dB iv=%dB"
                % (seq, tid(), state, nk, ni))
            return False

    class DecBreakpoint(gdb.Breakpoint):
        """eax_decrypt entry (streaming): rsi=ct rdx=pt rcx=len. Capture ct,
        arm finish for pt; tie back to the eax_init that made this state."""

        def stop(self):
            seq = next_seq()
            state = reg("rdi")
            ct_p, pt_p, length = reg("rsi"), reg("rdx"), reg("rcx")
            nc = dump(seq, "ct", read_mem(ct_p, min(length, MAX_BLOB)))
            log("DEC #%03d thread=%d state=0x%x init=#%s ct=%dB"
                % (seq, tid(), state, STATE_KEYS.get(state, "?"), nc))
            if pt_p and 0 < length <= MAX_BLOB:
                try:
                    NonStopFinish(gdb.newest_frame(), seq, pt_p, length, 0)
                except (gdb.error, ValueError) as e:
                    log("  #%03d finish arm failed: %s" % (seq, e))
            return False

    STATE_KEYS = {}  # eax_state ptr -> init seq (streaming correlation)

    class MarkerBreakpoint(gdb.Breakpoint):
        """Log-only marker: confirm the high-level path and probe the arg
        registers as std::string to spot the incoming item_blob."""

        def __init__(self, spec, tag):
            super(MarkerBreakpoint, self).__init__(spec)
            self.silent = True
            self.tag = tag

        def stop(self):
            probes = []
            for rn in ("rdi", "rsi", "rdx", "rcx"):
                s = decode_string(read_mem, reg(rn))
                probes.append("%s=%s" % (rn, ("%dB" % len(s)) if s is not None else "?"))
            log("%s thread=%d %s" % (self.tag, tid(), " ".join(probes)))
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
        for cls, off, tag in ((DvmBreakpoint, OFF_EAX_DVM, "DVM"),
                              (InitBreakpoint, OFF_EAX_INIT, "INIT"),
                              (DecBreakpoint, OFF_EAX_DEC, "DEC")):
            bp = cls("*" + hex(base + off))
            bp.silent = True
            log("armed %s at 0x%x" % (tag, base + off))
        for off, tag in ((OFF_ENC_DEC, "ENC-DEC"), (OFF_ITEM, "ITEM")):
            MarkerBreakpoint("*" + hex(base + off), tag)
            log("armed marker %s at 0x%x" % (tag, base + off))

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
        log("run=%s base=0x%x pid=%s" % (RUN, base, gdb.selected_inferior().pid))
        install(base)
        gdb.execute("continue")

    main()
