# myTeamSpeak — handoff (2026-09-22, updated after run7 static KDF dig)

> Read with: `myteamspeak-sync-protocol.md` (wire reference),
> `myteamspeak-research-plan.md` (method, stop criteria),
> `myteamspeak-build-plan.md` (milestones), `docs/proto/README.md`.

## Where things stand

- **Phase 1 (static) done except task 1D (KDF).** All 23 TeamSpeak
  `FileDescriptorProto`s recovered from the binary and round-trip verified;
  the login/sync/user closure is committed in `docs/proto/` (commit
  `a41d5f4`). Request framing disassembled: `u8 len + method name + protobuf`,
  reply = bare protobuf on HTTP 200.
- **Phase 2 (capture) DONE for the login/sync/user/tschat closure (run6).**
  In-process gdb read RPC bodies as plaintext before TLS. On the wire:
  framing and bare-protobuf reply **confirmed**; body arg is `rcx` (the old
  `rdx`/`r9` note was wrong). Real service→method mapping captured (see the
  wire reference §0). **Q2 answered** (`requestServerItems` pulls,
  `synchronizeItems` pushes). **Q4 answered: item payloads are encrypted**
  (`item_blob` ~7.5 bits/B entropy, no `Item_Data` parse).
- **→ Next critical path: task 1D (KDF).** The sync blobs are opaque, so the
  key derivation / AEAD unwrap must be reversed before any item read/write in
  the app. The same gdb approach can read the plaintext `Item_Data` + key/iv
  at the decrypt call (wire reference §7).
- **M0 (app) partly done** (commit `c41d1ef`): `kotlinx.serialization`
  bookmarks + tests, `captures/` git-ignored. Missing: okhttp,
  security-crypto, protobuf deps; the golden decode test can now use a run6
  request payload (replies are encrypted).

## Capture attempts (runs 3–5, 2026-09-22)

Throwaway myTS account, isolated client profile. The user logged in, added 2
bookmarks, 1 contact and a chat in run 3, so the account has known content.

| Run | Setup | Result |
|---|---|---|
| 3 | `HTTPS_PROXY` env → mitmdump | Login works, but only gRPC `push.myteamspeak.com:8876` uses the proxy (and fails). `clientapi` goes **direct**: cpp-httplib ignores proxy env. |
| 4 | + `LD_PRELOAD` connect shim, no proxy env | No log in the shim yet; client shows **"Network is offline!"**. |
| 5 | shim with logging | Shim redirects the right connections (`clientapi` included), proxy answers `200 Connection established`, then the client closes: no HTTP flow, empty `.mitm`, addon `tls_failed_client` logged nothing. Client shows **"Offline"**. |

Most likely cause (unproven): the client does not trust the mitmproxy CA.
OpenSSL is statically linked, so `SSL_CERT_FILE` may be ignored, or the
certificate is pinned, or it verifies after the handshake and drops quietly.
**Conclusion: routing is solved; TLS interception is not** — which is why
run6 switched to reading plaintext in-process (below).

## run6 (2026-09-22): in-process gdb capture — DONE

No certificates involved: launch the isolated client **as a child of gdb**
(`kernel.yama.ptrace_scope = 1` forbids attaching later) and break where the
body is still plaintext. Addresses are for the pinned build (md5
`8234f961…`), PIE → add the load base (`info proc mappings`, first
`/opt/teamspeak/TeamSpeak` mapping; run6 base was `0x555555554000`).

- **Request:** `0x1dfd82a` — `call QWORD PTR [rax+0x18]` (cpp-httplib POST).
  Confirmed args: `rsi` = URL `std::string*`, **`rcx` = body `std::string*`**
  (the framed `u8 len + method + protobuf`), `r8` = content type
  (`application/ts3cloud`). **`rdx` is empty and `r9` is not the response** —
  the pre-run6 note was wrong.
- **Reply:** `0x1dfde0b` — `call 289f050` (`ParseFromString`): `rsi` = data,
  `rdx` = length. Dump `rdx` bytes from `rsi` — this is the reliable reply
  source (the response is the call's return value, not `r9`).
- libc++ `std::string`: byte 0 bit 0 set → long form (size at +8, data
  pointer at +16); clear → short form (size = byte0 >> 1, data at +1).
- Bodies land in `captures/myts/<run>-<seq>-POST-<host>-<path>.{req,resp}.bin`
  so `tools/myts/analyze.py captures/myts/<run>` decodes them unchanged.
- **Known limit:** reply↔request correlation is per-thread "first PARSE after
  REQ"; during the startup burst thread 78 fires several REQs before their
  replies parse, so some pull replies (`requestServerItems`) get mis-paired.
  Single user-triggered writes (`synchronizeItems`) correlate cleanly. To
  capture pull replies cleanly, dump every `ParseFromString` buffer to its own
  file instead of pairing.

**Next (task 1D):** break at the item decrypt/AEAD call, feed a captured
`item_blob` back, and read the plaintext `Item_Data` + key/iv there.

## run7 (2026-10-12): static KDF dig via Ghidra — IN PROGRESS, not done

Goal: reverse `getAccountHashedPassword` (the plaintext→48-byte wire-password
transform, [[myts-login-wire-password]]). Static only, no capture.

**Tooling note:** there is already a *manually built* Ghidra project at
`captures/myts/ghidra/tsclient.gpr` (program `TeamSpeak`, md5 `8234f961…`,
full analysis already run, repo ~546 MB) — reuse this, don't re-import. The
`rea` MCP tool does **not** know about this project (its own cache under
`/var/tmp/rod-ghidra/` only has a type archive) and re-runs full analysis on
`open_binary`/`binary_overview`/`procedure_pseudo_code` for this target,
which times out (>300s) on this 66 MB stripped binary — happened 4 times
across two sessions. Workaround: drive the existing project directly with
`analyzeHeadless` + a disposable Java `GhidraScript` (Jython/PyGhidra is not
configured in this install, so scripts must be `.java`, not `.py`):

```bash
/opt/ghidra/support/analyzeHeadless captures/myts/ghidra tsclient \
  -process TeamSpeak -noanalysis \
  -scriptPath tools/ghidra_scripts -postScript <Script>.java
```

`-noanalysis` skips re-analysis (the project already has it) but leaves some
addresses without a `Function` object even when code exists there (e.g.
vtable thunks) — create it on demand with
`new ghidra.app.cmd.function.CreateFunctionCmd(addr).applyTo(currentProgram, monitor)`
before decompiling. `GHIDRA_INSTALL_DIR=/opt/ghidra` was added to `.mcp.json`
for `rea` itself (Ghidra 12.1.2, matches `pacman -Qi ghidra`), but that only
fixed rea's "not configured" error, not the timeout.

**Findings so far** (binary is stripped; `FUN_xxx` names are Ghidra
auto-names, not real symbols — only string literals and C++ mangled names
embedded in rodata survived stripping):

- The literal string `"getAccountHashedPassword"` lives at `0x6b6078`, but
  it's RPC-dispatcher plumbing, not the hash: it's referenced only from
  `FUN_01aa5d20` (`@ 0x1aa5d20`), a giant function that registers ~40 RPC
  method names (`getAccountHashedPassword`, `validatePassword`,
  `getBackupKey`, `getAccountUsername`, …) each as a name→handler-object pair
  into a dispatch map (`FUN_01ac9e30`). The handler object's vtable (e.g.
  `PTR_LAB_03ee2688` for this entry) is a generic type-erased
  functor/continuation wrapper (dtor/delete/invoke slots at +0/+8/+0x10); the
  invoke slot (`FUN_01acf7b0`) just forwards through *other* captured
  objects' vtables — it is not where the crypto happens. **Don't follow this
  path further**, it's a dead end for the KDF itself (useful only to
  enumerate the full RPC method list, which may be worth doing separately).
- The real lead is the assert string from [[myts-login-wire-password]]:
  `"Assertion \"plain_hash.size() == teamcrypto::sha2::sha512_size\" failed
  at .../Encryption.cpp:"` at `0x4e3e32`. Its only xref is
  `FUN_01dee970 @ 0x1dee970`, which does check a buffer length against `0x40`
  (64 — sha512 digest size) before taking one of two branches.
- Call chain above that confirmed so far (all thin wrappers, one call each,
  no real logic):
  `FUN_01dee950 @ 0x1dee950` → `FUN_01dee970`
  `FUN_01def210 @ 0x1def210` → `FUN_01dee970`
  `FUN_01def110 @ 0x1def110` → `FUN_01dee970`, then conditionally
  `FUN_01df03e0 @ 0x1df03e0` → `FUN_01bf2f80` (not yet decompiled)
- One level further up, `FUN_01de5430 @ 0x1de5430` calls
  `FUN_01de6d00(&buf, 0x20, &out)` (`0x20` = 32 bytes — matches
  `encryption_password` size in [[myts-login-wire-password]]) **then**
  `FUN_01def210` (the sha512-size-checked path), and assembles a result
  record that looks like **two concatenated 32-byte halves** (offsets
  `+0x14..+0x34` and `+0x34..+0x54` relative to the output struct) — i.e. one
  candidate shape for a 64-byte sha512 digest split in half, or two
  independently-derived 32-byte values. Neither matches 48 bytes directly;
  the 48-byte wire value is presumably a further truncation/selection not
  yet located.
  `FUN_01de72e0 @ 0x1de72e0` is a sibling caller of `FUN_01dee950` with
  similar shape (conditional on a length field `local_54 != 4`).
- `FUN_01de6d00` itself (the "build N-byte buffer" helper, called with
  `N=0x20` above) is generic/parameterized: it does not hash inline but
  drives a **stream/digest object through its vtable** (opens, feeds twice,
  finalizes via `FUN_01ec3d20`, `FUN_01d83db0`, `FUN_01d80e80`/`FUN_01d80e00`,
  `FUN_01c69360`, then writes `param_3` bytes out via `FUN_01d84910`). This
  is almost certainly the shared KDF/digest primitive used for **all** of
  `encryption_password` (32B), `key` (48B) and the wire password (48B) —
  called with a different output-length parameter each time — rather than
  one bespoke function per field.
- Callers one level above the two entry points seen so far (not yet
  decompiled): `FUN_01de5430` ← `FUN_01de5780`, `FUN_01d99260`;
  `FUN_01de72e0` ← `FUN_01de8080`, `FUN_01de85f0`, `FUN_01de8970`,
  `FUN_01de8420`. These are plausibly the per-field entry points
  (`getAccountHashedPassword`, `getBackupKey`'s hash, `encryption_password`
  derivation, …) that each call the shared KDF helper with their own length
  and salt/context — worth decompiling next to tell them apart by the
  constants they pass in.

**Where to pick this up:** decompile `FUN_01ec3d20`, `FUN_01d83db0`,
`FUN_01d80e80`, `FUN_01d80e00`, `FUN_01c69360` (the digest-object stream
interface — this is where it should become clear whether it's a straight
SHA-512, an HMAC, or a PBKDF2/iterated construction, and where the plaintext
password and any salt actually enter), then come back to the five
undecompiled callers above to tell the 32B/48B/64B call sites apart. Use the
`DumpFuncs.java` / `FindCallers.java` pattern above (disposable scripts, edit
the address list, rerun `analyzeHeadless`); they are **not kept in the repo**
(deleted after use each round) — recreate them from this doc if needed, or
check `tools/ghidra_scripts/` first in case a later session left one.

## run8 (2026-10-12): decompiled the "digest" helper internals — plot twist, likely Ed25519, not a hash

Decompiled the 5 functions listed above (`DumpFuncs.java` target list edited
in place, same `analyzeHeadless -noanalysis -postScript DumpFuncs.java`
invocation as run7; output kept in session scratch, not committed).

- `FUN_01ec3d20`: generic lifecycle dispatcher, not crypto. Takes a flag in
  `unaff_ESI` (0 or 1) and placement-`new`s one of two object types (two
  distinct vtables, `PTR_LAB_03f0e2e0` vs `PTR_LAB_03f0e288`), destroying
  whatever was in the output slot before. This is a "construct/replace
  polymorphic member" helper, generic across many unrelated object types in
  this codebase — **not specific to the KDF**, dead end for algorithm ID.
- `FUN_01c69360`: generic cleanup/free gated on a liveness flag
  (`local_38 != 0`). Also generic RAII, **not crypto-specific**.
- `FUN_01d80e00`: thin wrapper, feeds two 40-byte buffers through a function
  pointer (`DAT_04052af8`, itself vtable-ish/global-dispatched) and XORs one
  result bit into a flags byte. Not enough here alone to identify the
  algorithm; needs `DAT_04052af8`'s target resolved.
- **`FUN_01d83db0` and `FUN_01d80e80` are the interesting ones — strong
  Curve25519/Ed25519 fingerprint, not a conventional digest:**
  - `FUN_01d83db0` unpacks two 32-byte inputs into limbs and does field
    arithmetic with the exact magic constants `0x215d1`, `-0xa6f7d`,
    `0x9fb67`, `0x72d18`, `0xa2c13`, `-0xf39ad` on 21-bit-windowed limbs —
    this is the textbook `ref10`/`donna`-style radix-2^25.5 field
    multiplication/reduction used in Curve25519/Ed25519 implementations, not
    SHA-2/HMAC/PBKDF2 round constants (checked: these don't match any SHA-2
    K-table, Blake2 IV, or ChaCha constant either).
  - `FUN_01d80e80` takes a 32-byte input, decomposes it into 64 4-bit
    "nibbles" with a `+8` bias / `& 0xf0` carry-propagation pass (classic
    signed-digit scalar recoding), then drives a 64-iteration double-and-add
    loop through `FUN_01d81550` + a handful of point-arithmetic helpers
    (`FUN_01d819d0`, `FUN_01d82a80`, more behind `DAT_04052af8`/`af0`/`b00`).
    This is the `slide()` + double-base scalar-multiplication shape used in
    Ed25519 **signature verification** (`ge_double_scalarmult_vartime`-style),
    not a hash finalize step.

**Revised hypothesis:** the object `FUN_01de6d00` drives through its vtable
is a generic crypto-primitive interface (shared base class) that, in *this*
instantiation, resolves to Ed25519 scalar-mult/verify machinery rather than a
SHA-512 digest. Two explanations to distinguish next:
1. This vtable slot is a red herring for the password KDF specifically —
   `FUN_01de6d00` may be generic/reused code, and the 32B call site reached
   via `FUN_01de5430` in run7 might dispatch to a *different* concrete vtable
   (sha512) than the one just decompiled, depending on which type got
   constructed by `FUN_01ec3d20`'s flag at that call site.
2. The "hash" really is Ed25519-based (e.g. deriving the 48-byte value from
   a point/scalar operation rather than a pure digest) — would explain why
   no offline sha2/hmac/pbkdf2/scrypt guess ever matched.

**Next step:** resolve which concrete vtable (`PTR_LAB_03f0e2e0` vs
`PTR_LAB_03f0e288`, from `FUN_01ec3d20`) is actually constructed at the 32B
call site in `FUN_01de5430`/`FUN_01de72e0`, and what `DAT_04052af8`/`af0`/
`b00` point to (global function-pointer table — likely more vtable dispatch,
worth resolving via `xrefs`/`list_names` on those addresses in the same
Ghidra project). Then decompile the five still-unseen callers
(`FUN_01de5780`, `FUN_01d99260`, `FUN_01de8080`, `FUN_01de85f0`,
`FUN_01de8970`, `FUN_01de8420`) to see which length/constant combination
reaches the Ed25519 path vs. a plain-digest path, if one exists.

## run9 (2026-10-12): decompiled the 32B call site (`FUN_01de5430`) — two-value result, still not isolated

`tools/ghidra_scripts/InspectData.java` (disposable, same pattern, deleted
after use): resolved `DAT_04052af8`/`af0`/`b00` — **unreadable statically**
("Unable to read bytes"), confirming they're GOT/lazy-bound function
pointers resolved only at runtime, not something `-noanalysis` static
decompile can follow. Dropping that sub-lead; would need a live
breakpoint/read (gdb, like run6) to resolve, not more static Ghidra.

Decompiled `FUN_01de5430` (the 32B call site) and `FUN_01de72e0` (its sibling,
unconditional length-4 check) in full:

- `FUN_01de5430` confirms the exact sequence guessed in run7:
  `FUN_01de6d00(&local_98, 0x20, &local_bc)` — builds a 32-byte buffer
  (`local_98`) — **then** `FUN_01def210(uVar5, &local_c0)` — the sha512-size
  asserted path — is called *on the object/pointer `FUN_01de6d00` just
  returned*, not on raw input bytes. So `FUN_01de6d00`'s 32-byte output is
  an intermediate (likely salt/context material or a half-built digest
  state), and `FUN_01def210` is the step that actually does the
  size-checked (64-byte/sha512) digest operation, writing its own 32-byte
  result into `local_c0`.
- The function then assembles an output record containing **both** 32-byte
  values side by side (one branch copies `local_bc`'s 32 bytes to
  output+0x14, the other copies `local_98`'s 32 bytes to output+0x34,
  conditionally on two different liveness flags, `local_c0 != -1` and
  `local_9c != -1`). This isn't necessarily "the password is 64 bytes
  split in half" — it now looks more like a generic multi-field response
  struct (e.g. {status, value_A?, value_B?}) that this RPC-plumbing layer
  reuses for several different calls, where only one of the two 32-byte
  slots may end up being the actual `encryption_password` field and the
  other is incidental (an error/alternate path's leftover buffer, or a
  second unrelated output of the same low-level op). Not yet proven either
  way.
- The `plVar2`/`PTR_LAB_03f032f8` branch (the `local_f0 & 1` byte-1 case) is
  a continuation/promise object allocation — same async-result-wrapper
  pattern seen elsewhere in this client, **not an alternate crypto path**.
  Confirms this function is just assembling an async result, consistent
  with run8's finding that `FUN_01ec3d20`/`FUN_01c69360` are generic
  lifecycle helpers, not crypto.
- `FUN_01de72e0` (sibling, presumably the 48B/64B case) has the same shape
  but calls `FUN_01dee950` instead of `FUN_01def210` directly, guarded by
  `local_54 != 4` (a length/mode check — `4` is suspicious, maybe a tag enum
  rather than a byte length) and an extra capability gate
  (`FUN_0299fc10()` returning non-zero before it even tries). Haven't
  resolved what `local_54 == 4` means yet.

**Open problem, unresolved after 3 sessions on this:** we still have not
pinned down the exact byte-for-byte transform. The Ed25519-shaped functions
from run8 (`FUN_01d83db0`, `FUN_01d80e80`) have **not yet been proven to be
on the call path actually reached from `FUN_01de5430`** — they were reached
by decompiling `FUN_01ec3d20`'s *object-type dispatch targets* in isolation,
not by tracing concrete execution from this specific 32B call site. The
GOT-pointer dead end (`DAT_04052af8` etc.) means the remaining ambiguity
(which vtable/digest-object type is actually live here) **cannot be
resolved by more static Ghidra decompilation** — it needs a dynamic check.

## run10 (2026-10-12): exact ABI at the 32B call site — ready for the dynamic pivot

One more static step before switching to gdb: disassembled (not just
decompiled) `FUN_01de6d00`'s entry and the call site inside `FUN_01de5430`
(`tools/ghidra_scripts/DumpAsm.java`, disposable, deleted after use) to get
the real register ABI, since the C pseudocode drops args into
`unaff_*`/globals that don't show the call-site mapping.

Call site (`FUN_01de5430` @ `0x1de5464..0x1de54c0`):
```
MOV RSI,RBP ; CALL FUN_01d87690         ; FUN_01d87690(this=?, RBP)
LEA R14,[RSP+0x60]                      ; R14 = scratch/"input" slot
LEA RDI,[RSP+0x80] ; (zeroed, 64B)      ; RDI = dest/out buffer (32B used)
LEA R15,[RSP+0x3c]                      ; R15 = context/"salt" slot
MOV EDX,0x20 ; MOV RSI,R14 ; MOV RCX,R14 ; MOV R8,R15
CALL FUN_01de6d00                       ; (out, in=R14, len=0x20, in_dup, ctx=R15)
...
MOV RSI,[R13] ; LEA RDI,[RSP+0x8] ; MOV RDX,RBP
CALL FUN_01def210                       ; (out2, hash_obj=[R13], this=RBP)
```
`RBP` is the one register alive across the *whole* sequence — it is reused
both as the arg to `FUN_01d87690` at the top and as the final arg to
`FUN_01def210` at the bottom. Working hypothesis: `RBP` is `this`, the
object holding the plaintext password (or the whole login-credentials
object) for this call.

`FUN_01de6d00`'s own entry confirms the two-feed shape guessed in run7/8,
**and nails which object type is actually constructed here** — resolving
the open question from run8/9 statically after all (no need for the GOT
dead end):
```
LEA RDI,[RSP+0x8] ; MOV ESI,1 ; CALL FUN_01ec3d20   ; construct w/ flag=1 → PTR_LAB_03f0e2e0
MOV RDI,[RSP+8] ; MOV RAX,[RDI]
MOV EDX,0x20 ; MOV RSI,RBX(=ctx/"salt" ptr, the caller's R8)
CALL [RAX+0x10]                                      ; feed(ctx, 32)         <- FIXED length
MOV RDI,[RSP+8] ; MOV RAX,[RDI]
MOV RSI,R12(=in ptr, caller's RSI) ; MOV RDX,R15(=caller's len, 0x20)
CALL [RAX+0x10]                                      ; feed(in, len)         <- caller's length
LEA RDI,[RSP+0x30] ; LEA RSI,[RSP+8] ; CALL FUN_01c69360   ; move/destroy ctor temp
MOV RDI,[RSP+0x30] ; CALL FUN_01d83db0                     ; "finalize" step 1
MOV RSI,[RSP+0x30] ; LEA RDI,[RSP+0x50] ; CALL FUN_01d80e80 ; "finalize" step 2
```
So: **the flag=1 vtable (`PTR_LAB_03f0e2e0`) is confirmed live on this exact
32B call path, and its finalize genuinely routes through `FUN_01d83db0`
(Curve25519-style field arithmetic) and `FUN_01d80e80` (Ed25519-style
scalar-recode + double-and-add) from run8** — this was not a red herring.
The call shape is `feed(context_32B)` then `feed(input_32B)` then finalize —
a salted/keyed-hash shape, but with an elliptic-curve finalize instead of a
plain compression function.

**Revised, sharper hypothesis:** this is very plausibly computing something
like `scalar = reduce(H(context ‖ input))` then `point = scalar * basepoint`,
encoded as 32 bytes — i.e. deriving an **X25519/Ed25519 public key from the
password** (and a fixed/derivable 32-byte context) rather than a
conventional salted hash. If true, `encryption_password` (32B) would decode
as a Curve25519 point encoding, which is independently checkable (valid
Curve25519 points have a restricted/parseable form) once we have a captured
output byte string.

**Why this still needs gdb, not more Ghidra:** we now know *which*
functions run at this call site, but not the exact byte-level content of
the "context" (`R15`/`RBX`, origin not yet traced — could be a per-call
constant, a hash of the email/uuid, or literal zero) nor whether the
password bytes reach `R14`/`R12` directly or via another transform inside
`FUN_01d87690` first. Both are a few-instruction static trace away in
principle, but confirming byte values (is the context really constant? does
it match the account's email/uuid?) is faster and more certain read directly
out of the running process during an actual login, against the known-good
test vector in `captures/myts/reverse-password-prompt.md` (gitignored, not
duplicated here). Proceeding with the dynamic pivot as planned.

**Recommended next step is a change of method, not more static digging:**
reuse the run6 gdb approach (`tools/myts/gdb_capture.py` pattern, already
proven to attach to this exact binary and dump register/memory state at
chosen addresses) to put a breakpoint at `FUN_01de6d00`'s entry and at
`FUN_01def210`'s entry during an actual login, and dump: (a) the plaintext
password buffer going in, (b) the resolved vtable pointer (first qword of
the object `FUN_01ec3d20` constructed, to diagonse sha512 vs Ed25519 branch
by comparing against `PTR_LAB_03f0e2e0`/`PTR_LAB_03f0e288`), (c) the 32-byte
intermediate (`local_98`-equivalent) and the final digest output, all
against the already-known-good 48-byte wire-password test vector from
[[myts-login-wire-password]]. That turns "which object type is this" from a
static-analysis guess into a single memory read. Static Ghidra digging on
this specific question (call-site → concrete vtable) has hit diminishing
returns after run7–9; don't keep spending further sessions re-decompiling
more of the surrounding plumbing without switching to the dynamic check
first.

## run13 (2026-10-13): fresh login exercised — DIGEST/WRAP hypothesis falsified

Cleared the isolated profile (`captures/myts/profile/{config,cache}`, backed up
to `profile-backup-20261013-204929`) to force a real `LoginData{email,
password,...}` flow instead of session-token reuse, then re-ran
`gdb_kdf.py` (`MYTS_RUN=run13`, same breakpoints as run11/12:
`FUN_01de6d00`/`DIGEST-entry`, `FUN_01def210`/`WRAP-entry`). User logged in
by hand in the client window (confirmed success — normal UI loaded, 3
established TLS connections to `clientapi`'s IP + 1 to `push` on :8876).

- **`DIGEST-entry` never fired** (0 hits, matching run11/12).
- **`WRAP-entry`** fired ~98 times, all within the first ~1.4s of process
  start (startup burst, same shape as run11/12: `out2` almost always `0x0`,
  `this` a small tag `0x4/0x6/0x8/0xc/0x21/0x41/-4`, never a pointer-shaped
  value — generic cert/cache hashing, not password-related).
- **Zero new hits of either breakpoint between process-start settling and
  >130s after a confirmed successful login.** The real `login` RPC (which
  must have gone out — the connections prove it) **does not pass through
  `FUN_01de6d00` or `FUN_01def210`.**

**Conclusion: the run7-10 static hypothesis is falsified.** Those two
functions are confirmed-generic (startup cert/cache hashing), not the
login password KDF. The Ed25519-shaped sub-functions found in run8
(`FUN_01d83db0`, `FUN_01d80e80`) may still be used *somewhere* in this
binary (possibly for identity/key signing, not password hashing), but not
reached from the login flow. **Do not re-arm these two breakpoints for KDF
work in a future session** — this is now a closed, negative result.

**Recommended next step (not yet done):** stop guessing the KDF function
from the sha512-assert string (`Encryption.cpp`) — that was always a weak
lead (one xref, generic size check). Instead:
1. Re-run `gdb_capture.py` (the run6 tool, not `gdb_kdf.py`) during a fresh
   login like this one, to capture the **actual `login` RPC request body**
   — this gives a ground-truth 48-byte wire-password tied to a known
   plaintext password (ethics/rule unchanged: never paste `--raw` output,
   masked by default).
2. With that ground truth in hand, search the Ghidra project for xrefs to
   the `LoginData` protobuf setter for its `password` field (or to
   `Account_Manager_Impl`/`Sync_Client_Lib_Impl`'s login entry points) rather
   than the generic digest helper — trace **forward** from "where does the
   plaintext password string get read" instead of backward from an assert
   string that turned out to be shared/generic plumbing.
3. Only resort to a memory-wide scan for the captured 48-byte value (to find
   which function last wrote it) if the xref approach stalls again.

Profile state: `captures/myts/profile/` now holds a **fresh, successfully
logged-in session** from this run (today's date) — reuse it for any future
capture that doesn't require re-login. The pre-run13 session is preserved in
`captures/myts/profile-backup-20261013-204929/` if needed for comparison.

## Tools (in `tools/myts/`, **not committed yet**)

- `capture_addon.py` — mitmproxy addon, dumps TeamSpeak-host flows and names
  the RPC. `MYTS_RUN=runN mitmdump --listen-host 127.0.0.1 --listen-port 8089
  -s tools/myts/capture_addon.py -w captures/myts/runN.mitm`.
- `gdb_capture.py` — **the run6 tool.** gdb Python script: runs the client
  under gdb, arms three non-stopping breakpoints (REQ `0x1dfd82a`, RET
  `0x1dfd82d`, PARSE `0x1dfde0b`), auto-detects the framed body register,
  dumps `.req/.resp.bin`, logs metadata only (never body bytes). Refuses any
  build but md5 `8234f961…`. `MYTS_DRY=1 gdb -batch -nx -x
  tools/myts/gdb_capture.py` runs preflight checks without launching.
- `analyze.py` — decodes `.req/.resp.bin` pairs with `docs/proto`, tries each
  `item_blob` as `Item_Data` (capture question Q4), masks secrets unless
  `--raw`. Self-tested on synthetic fixtures; works with protobuf 7.
- `connect_shim.c` — `LD_PRELOAD` redirect of `:443` to an HTTP CONNECT
  proxy, main process only, `MYTS_SHIM_LOG` for per-connect logging. Build:
  `gcc -shared -fPIC -O2 -o captures/myts/connect_shim.so
  tools/myts/connect_shim.c -ldl`.

## Local state (all git-ignored under `captures/myts/`)

- `profile/{config,cache}` — isolated client profile, **logged in to the
  throwaway account** (holds tokens). Reuse it; delete it to force a fresh
  login.
- `ca-bundle.pem` (system bundle + mitmproxy CA), `connect_shim.so`,
  `run3–5` logs/flows, `run6-*.{req,resp}.bin` + `run6-gdb.log` (the working
  capture), plus two harness smoke tests from 2026-09-09 (`run1`, `run2`,
  `session-1/2`).

Launching the isolated client **under gdb** (same profile, no proxy):

```bash
D=$PWD/captures/myts; SCRIPT=$PWD/tools/myts/gdb_capture.py
(cd $D && env XDG_CONFIG_HOME=$D/profile/config XDG_CACHE_HOME=$D/profile/cache \
  MYTS_RUN=runN setsid nohup gdb -batch -nx -x "$SCRIPT" \
  --args /opt/teamspeak/TeamSpeak > $D/runN-client.log 2>&1 &)
```

Stop it by PID after checking `/proc/<pid>/environ` has that
`XDG_CONFIG_HOME` — the user's normal instance (`/usr/bin/teamspeak`) runs
alongside and must not be touched. Find gdb with `pgrep -x gdb` (matches the
process name exactly; a `-f` pattern also matches the shell command line and
returns extra PIDs). Killing the gdb PID also closes the client child.
`ptrace_scope=1` blocks attaching to a running client, so gdb must *launch*
it. TeamSpeak is CEF/Chromium multiprocess, but the cpp-httplib RPC runs on a
worker thread of the browser process (the one gdb launches), so
`follow-fork-mode parent` keeps the breakpoints live.

## Gotchas

- **Ask before launching or killing anything.** The user watches the client
  window and reports its state; stop everything as soon as they say so.
- Port 8080 is taken on this machine; use 8089.
- On start with a custom `XDG_CONFIG_HOME` the client runs
  `xdg-desktop-menu uninstall` on its own. Harmless here (the system
  `teamspeak.desktop` entry is intact), but expected.
- Never use the real account; never paste `--raw` output, tokens, emails or
  public IPs into docs (research plan §3).
