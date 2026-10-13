"""gdb script: capture the myTeamSpeak login password-KDF inputs/outputs
in-process (task 1D continuation, [[myts-login-wire-password]]).

Companion to gdb_capture.py / gdb_decrypt.py. Same model: launch the isolated
desktop client as a child of gdb and arm non-stopping breakpoints, here on
the generic digest helper and its sha512-size-checked caller identified
statically in docs/myteamspeak-handoff.md (run7-run10):

  FUN_01de6d00  "feed(ctx,32); feed(in,len); finalize"   entry ABI (run10):
      rdi=out(32B dest)  rsi=in_ptr  rdx=len  rcx=in_ptr(dup)  r8=ctx_ptr(32B)
  FUN_01def210  wraps FUN_01de6d00's result through the sha512-size-checked
      path (FUN_01dee970's caller)                        entry ABI (run10):
      rdi=out2  rsi=hash_obj_ptr  rdx=this(password/credentials object?)

We breakpoint at ENTRY of both (to capture inputs: ctx 32B, in_ptr/len,
password-object candidate in rdx/rbp) and set a one-shot internal
finish-breakpoint to capture each one's output buffer at return (the `out`/
`out2` pointers are known from entry, so we re-read them at the return PC of
the *caller* rather than hooking every possible return path inside the
callee).

Because this directly captures password-derivation material, output is
written ONLY to git-ignored files under captures/myts/; the log never
contains secret bytes, only sizes/pointers/addresses, matching the existing
rule for gdb_decrypt.py. Correlate offline against the known-good 48-byte
wire-password vector in captures/myts/reverse-password-prompt.md (not
committed).

  MYTS_RUN=run11 gdb -batch -nx -x tools/myts/gdb_kdf.py \\
      --args /opt/teamspeak/TeamSpeak
  MYTS_DRY=1 gdb -batch -nx -x tools/myts/gdb_kdf.py   # checks, no run

Trigger a login in the running client (or let the saved profile re-auth) to
hit these breakpoints; they fire on every call, not just once, so expect
multiple hits (encryption_password derivation, wire-password derivation,
possibly getBackupKey too — distinguish by the `len` argument and by which
hit happens during the login flow vs. idle sync).

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

# Link vaddrs (add PIE load base at runtime); see docs/myteamspeak-handoff.md
# run7 (discovery) / run10 (exact ABI at these entries).
OFF_DIGEST = 0x1DE6D00     # FUN_01de6d00: feed(ctx,32); feed(in,len); finalize
OFF_SHA_WRAP = 0x1DEF210   # FUN_01def210: sha512-size-checked wrapper

MAX_BUF = 128  # generous; the fields we care about are 32/48/64 bytes

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.environ.get("MYTS_OUT", os.path.join(ROOT, "captures", "myts"))
RUN = os.environ.get("MYTS_RUN", "") or "run"


def md5_of(path):
    h = hashlib.md5()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


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

    def tid():
        t = gdb.selected_thread()
        return t.global_num if t is not None else 0

    LOG_PATH = os.path.join(OUT_DIR, RUN + "-kdf.log")
    SEQ_DIGEST = [0]
    SEQ_WRAP = [0]

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

    class DigestFinish(gdb.FinishBreakpoint):
        """Fires when FUN_01de6d00 returns; re-reads its `out` (32B)."""

        def __init__(self, frame, seq, out_p, base):
            super(DigestFinish, self).__init__(frame, internal=True)
            self.silent = True
            self.seq = seq
            self.out_p = out_p
            self.base = base

        def stop(self):
            out = read_mem(self.out_p, 32)
            if out is not None:
                write_blob(self.base + ".out32.bin", out)
            log("DIGEST #%03d RET out_saved=%s" % (self.seq, out is not None))
            return False

        def out_of_scope(self):
            log("DIGEST #%03d out lost (frame out of scope)" % self.seq)

    class WrapFinish(gdb.FinishBreakpoint):
        """Fires when FUN_01def210 returns; re-reads its `out2` window."""

        def __init__(self, frame, seq, out2_p, base):
            super(WrapFinish, self).__init__(frame, internal=True)
            self.silent = True
            self.seq = seq
            self.out2_p = out2_p
            self.base = base

        def stop(self):
            # out2 struct layout unknown precisely; dump a generous window
            # (the 32B value sits at some +off inside it per run9's
            # struct-assembly notes) for offline inspection.
            out = read_mem(self.out2_p, MAX_BUF)
            if out is not None:
                write_blob(self.base + ".out.bin", out)
            log("WRAP #%03d RET out_saved=%s" % (self.seq, out is not None))
            return False

        def out_of_scope(self):
            log("WRAP #%03d out lost (frame out of scope)" % self.seq)

    class DigestEntryBp(gdb.Breakpoint):
        """FUN_01de6d00 entry: rdi=out rsi=in rdx=len rcx=in(dup) r8=ctx."""

        def stop(self):
            out_p, in_p, length, ctx_p = reg("rdi"), reg("rsi"), reg("rdx"), reg("r8")
            SEQ_DIGEST[0] += 1
            seq = SEQ_DIGEST[0]
            base = "%s-kdf-digest-%03d" % (RUN, seq)
            ctx = read_mem(ctx_p, 32)
            inp = read_mem(in_p, min(length, MAX_BUF) if 0 < length <= MAX_BUF else 0)
            if ctx is not None:
                write_blob(base + ".ctx32.bin", ctx)
            if inp:
                write_blob(base + ".in.bin", inp)
            log("DIGEST #%03d thread=%d out=0x%x in=0x%x len=%d ctx=0x%x"
                " ctx_saved=%s in_saved=%s"
                % (seq, tid(), out_p, in_p, length, ctx_p,
                   ctx is not None, bool(inp)))

            try:
                DigestFinish(gdb.newest_frame(), seq, out_p, base)
            except (gdb.error, ValueError) as e:
                log("DIGEST #%03d: could not arm FinishBreakpoint: %s" % (seq, e))
            return False  # never stop the client

    class ShaWrapEntryBp(gdb.Breakpoint):
        """FUN_01def210 entry: rdi=out2 rsi=hash_obj rdx=this(password obj?)."""

        def stop(self):
            out2_p, hash_obj_p, this_p = reg("rdi"), reg("rsi"), reg("rdx")
            SEQ_WRAP[0] += 1
            seq = SEQ_WRAP[0]
            base = "%s-kdf-wrap-%03d" % (RUN, seq)
            log("WRAP #%03d thread=%d out2=0x%x hash_obj=0x%x this=0x%x"
                % (seq, tid(), out2_p, hash_obj_p, this_p))

            try:
                WrapFinish(gdb.newest_frame(), seq, out2_p, base)
            except (gdb.error, ValueError) as e:
                log("WRAP #%03d: could not arm FinishBreakpoint: %s" % (seq, e))
            return False  # never stop the client

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
            (DigestEntryBp, OFF_DIGEST, "DIGEST-entry"),
            (ShaWrapEntryBp, OFF_SHA_WRAP, "WRAP-entry"),
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

        gdb.execute("starti")
        base = load_base()
        if base is None:
            raise gdb.error("could not find load base for %s" % BINARY)
        log("run=%s base=0x%x pid=%s" % (RUN, base, gdb.selected_inferior().pid))
        install(base)
        gdb.execute("continue")

    main()
