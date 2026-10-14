# myTeamSpeak — handoff (2026-09-22, updated after run7 static KDF dig)

> **Latest session (2026-10-14): read
> [myteamspeak-login-run40.md](myteamspeak-login-run40.md) first.** The supplied
> `../teamspeak-client` is a different build. Run40 demonstrated the login KDF
> (PBKDF2-HMAC-SHA512, 10,000 iterations, 48 bytes, Base64) and a successful
> standalone `/authentication login` with `sync_version=V1_1`. Flutter is the
> target app; no application changes were made. Do not reuse the historical
> offsets or separate-Beast-login conclusion for this build. Research clients
> and debug ports are closed; sync decryption and renewal remain open.

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

## run14 (2026-10-13): fresh-login RPC capture — `login` bypasses the hooked POST

Goal: run13 rec step 1 — capture the real `login` RPC during a fresh login.
Profile wiped (backed up to `profile-backup-run14-20261013-210348`),
`gdb_capture.py` with `MYTS_RUN=run14`, user logged in by hand with the
throwaway account (success confirmed, fresh `AccountData` + `ProtobufItems`
in the profile afterwards). gdb stopped cleanly after; normal instance
untouched.

- **Negative result: 13 RPCs captured, zero `login` / `requestAuthToken` /
  `session` on `/authentication`.** First REQ (~26 s after arming, right at
  login) is already `requestServerItems` carrying a valid session. The login
  RPC does **not** go through the `com::teamspeak::rpc::Channel` worker POST
  at `0x1dfd82a` — same hook that catches every other RPC. Hypotheses (not
  yet tested): a different native HTTP client/call site, or a CEF/website
  flow (`www.myteamspeak.com/api`) with tokens handed to the native layer.
- **Positive side (fresh-sync ground truth):** `requestServerItems` with
  `globalversion: 00000000-0000-0000-0000-000000000000` (zero UUID = no
  cursors); **`sync_version: V1_1` on every sync RPC** — the app sends
  `DEFAULT` (`MyTsViewModel.kt` `LOGIN_SYNC_VERSION`), fix to `V1_1`.
  New methods observed: `getContactList`, `requestContactsAvatar` (carries
  `AvatarRequestID` packed as `Any`). One fresh `synchronizeItems` CONFIG
  push (355 B blob) — new encrypted sample with known-default content.
  `getSignedBadges` replies parse as empty or fail — same per-thread
  mis-pairing limit as run6, don't trust those pairings.
- **Next:** (a) find the real login path — strings/Ghidra for the
  `www.myteamspeak.com/api` login call site or other HTTP POST sites;
  (b) static forward trace from the confirmed demangled anchors
  `Account_Manager_Impl::setup_sync_account_using_authentication_token`,
  `request_password_from_user`, `LoginDataJson` (all present in the binary);
  (c) one-line app fix: `LOGIN_SYNC_VERSION = V1_1`.

## run15 (2026-10-13): ts3cloud-xref hunt + bridge table decode — login entry narrowed

Q: where does the native `login` go, given run14 proved it bypasses the
hooked Channel POST? Two headless runs on the existing Ghidra project
(`tools/ghidra_scripts/FindTs3CloudXrefs.java`, kept; `DumpAsm.java`
retargeted, disposable ranges).

- `application/ts3cloud` has exactly **one** code xref: `0x1efd816` in
  `FUN_01efd410` (the Channel wrapper feeding the hooked worker). So there
  is a single native ts3cloud sender — login uses no native ts3cloud HTTP.
- `loginAccount` lives in the rodata bridge-name table next to
  `getMytsAccountState`, `tschat_addIdentifier`, … with xrefs from the two
  known registrars (`FUN_01aa5d20`, `FUN_01c7cb10`). Decoded entry shape
  (stack-built short `std::string` + numeric id, id passed *after* the name):
  `getMytsAccountState→201`, `tschat_addIdentifier→385`, … — a
  name→id dispatch table for `tsclient_internal.*`, handlers resolved by id
  elsewhere (not at the registration site, so no handler pointer to lift
  here). The 16-byte `MOVUPS` + overlapping dword (last xmm byte redundant)
  is compiler padding, not content.
- No code loads the `loginAccount` bytes at `0x5e7170` itself, so its entry
  is registered elsewhere or by id — static bridge-following stalls here;
  not worth another run7-style sink.
- Tooling note: Ghidra link addr = file offset + `0x100000` (verified on
  `loginAccount`, `getAccountHashedPassword`; the ts3cloud string definition
  starts one byte early at `...c0`). Use `addr - 0x100000` for `dd`/grep.
- **Next (dynamic, no profile wipe): memory-scan for the known 48-byte wire
  value.** It is live in the run14 session heap (Account/LoginData buffers).
  New script: scan heap for the pattern after login, plant read/write
  watchpoints on hits adjacent to account context, have the user log out +
  log in again, catch the writer with a backtrace — that site is the KDF
  output store (or a copy one frame below it). Watchpoint budget (4 debug
  regs) is fine; value bytes never leave `captures/`.

## run16–18 (2026-10-13): value-watch strategy — tooling post-mortem, strategy retired

Idea: scan the logged-in heap for the known 48-byte wire value
(`tools/myts/gdb_pwscan.py`, pattern extracted pre-launch into an ephemeral
112 B file, shredded after; never logged), plant hardware *write*
watchpoints, catch the KDF's writer at the next logout+login.

- Scan itself works: `find` covers ~1000 MB in <1 s; 24–26 ascii + 19–21 raw
  hits per run. Heap context hashes **recur across runs** (`6666a072`,
  `388217ff` at different ASLR addresses) — the at-rest Account buffer
  fingerprint, reusable without any watchpoint. Stacks show ascii+raw pairs
  16 B apart (transient RPC-serialization copies).
- Watchpoints don't: (a) first attempt armed stack/transient hits and left
  failed `Watch` objects that poisoned resume ("too many breakpoints",
  process died); (b) the stack filter `(addr >> 48) == 0x7fff` never matches
  48-bit addresses — stacks were never excluded; (c) `self.delete()` of the
  trigger inside its own stop handler **segfaults gdb** (coredumpctl:
  `/usr/bin/gdb SIGSEGV`, twice); (d) even heap insertions are racy on this
  ~100-thread Chromium target.
- Mechanistic verdict (beyond tooling): an at-rest Account copy's writer is
  the login *save* path, not the KDF — catching it would not yield the
  transform. Retire this strategy; keep the ctx-hash fingerprints and the
  `gdb_pwscan.py` scanner (fixed filter/deletion) for buffer location only.

## run19 (2026-10-13, in progress): login goes through Boost.Beast, not httplib

Reading file bytes around the `loginAccount` bridge-name table (Ghidra addr
minus `0x100000` slide) shows a packed NUL-separated name table, and right
next to it the real discovery: the binary vendors **Boost.Beast** HTTP
(`Beast_Downloader`, `ui::s3::DownloaderHandler`,
`ui::decentral::Downloader`, `updater::Downloader`) — the second native HTTP
stack run14/15 were missing. `https://www.myteamspeak.com/api/` is in the
binary (only website-API URL besides communities/register links, which
`main.js` never fetches). Working hypothesis: native login = Beast POST to
the website API, carrying the wire password; the KDF sits 1–2 caller levels
above the send site.
Next: xref hunt for `www.myteamspeak.com/api/`, `No myts authentication
token`, table base `ActivateReply` (same headless pattern) → DumpAsm the
send site → run6-style plaintext capture at the Beast layer during a fresh
login (answers Q1 + confirms wire value/framing) → trace callers backward
to the KDF.

Outcome (run19b–e): the `api/` URL sits in an **upload-flavored string
table** (`s3UploadDone`, `contentLength` neighbors) consumed through a
`{ptr,len}` string_view table inside `FUN_01c31af0`'s range — the two "code"
xrefs (`0x1c3289f/0x1c32909`) are **data slots, not instructions** (file
bytes are pointer/len pairs; DumpAsm correctly empty). So this site is the
website-API *upload* client, not login. The auth-error fn `0x1a47105` is a
2-line log stub with **zero callers** (dead/indirect — no static parent).
Static table-forensics has hit diminishing returns (run7 pattern); stop here.
**Next discriminator is metadata, not code: SNI capture.** At a fresh login,
run `tcpdump -i any tcp port 443` (or 1 s `ss -tnp` sampling) and read the
TLS ClientHello SNI / destination IPs: `www.myteamspeak.com` vs
`clientapi.myteamspeak.com` vs other. No cert breaking, no gdb, no Ghidra —
one session, decisive answer to "where does the login POST go", which then
selects the hook (Beast write site vs Channel vs CEF). Needs a profile wipe
+ hand-typed throwaway login like run14.

## run20 (2026-10-13): SNI discriminator — DONE, login = clientapi (+1 www precursor)

Method (handoff plan, rootless variant): user installed tcpdump; capture ran
under sudo in the user's own terminal
(`sudo tcpdump -i any tcp port 443 -w captures/myts/run20.pcap`, PID 118033).
Profile backed up (`profile-backup-run20-20261013-213100`) + wiped, isolated
client launched plain (no gdb, PID 118141, environ-verified), user hand-typed
the throwaway login. SNI parsed offline with a throwaway script
(`/tmp/opencode/sni_parse.py`, handles SLL2/linktype 276 — plain `tcpdump -r`
has no TLS dissector and tshark is not installed).

Timeline (client start 21:31:01, login confirmed by user before 21:31:49):
- 21:31:02 — startup burst: `ts3services`, `la.teamspeak.com`,
  `files.teamspeak-services.com` (update/revocation checks).
- **21:31:33 — exactly ONE `www.myteamspeak.com` connection.**
- **21:31:34–36 — NINE `clientapi.myteamspeak.com` connections** (1 + 8
  across two edge IPs). This 3 s burst is the only login-shaped cohort in the
  window and starts 1 s after the www hit.
- 21:31:51–52 — four more `clientapi` connections (post-login sync burst,
  after the user had already reported success — consistent with run13/14's
  `requestServerItems`/sync/user/tschat burst, not the login itself).
- Rest of window: `badges-content` (173, Cloudflare-shared IP with chat),
  `chat-5.tmspk.net` + `chat.teamspeak.com`, CEF/DoH noise
  (`dns.google`, `cloudflare-dns.com`, `*.googleapis.com` — Chromium, not auth).

Process attribution (post-hoc `/proc` socket walk, ESTABLISHED only): the
short-lived login cohorts were already closed; isolated main (118141) still
holds `chat-5.tmspk.net:443` (logged-in chat — confirms the login succeeded
in the isolated profile), CEF network-service holds update/badge/google
conns. So the www-vs-clientapi login cohort is **timing-attributed, not
process-attributed** — keep that caveat.

**Verdict:** the login POST goes to **`clientapi.myteamspeak.com`** (bulk),
preceded 1 s earlier by a **single `www.myteamspeak.com` hit** (precursor:
token page? version check? CEF?). The run19 "Beast → website API carries
login" hypothesis is demoted but not dead — the www hit is real and
login-adjacent. Run14 stands (Channel POST @0x1dfd82a carries no login), so
the clientapi login sender is **Beast-native or the CEF network stack** —
still to distinguish.

**Next (no wipe needed): per-process connect logger.** New tiny LD_PRELOAD
shim hooking `getaddrinfo`+`connect`, log-only, all processes incl. CEF
children: have the user log OUT and back IN in the running isolated client
(session logout → fresh login flow, no profile wipe) and see whether the
clientapi login burst originates from the main process (native/Beast) or the
`--type=utility …NetworkService` child (CEF). That selects the hook: Beast
write site vs CEF network stack.

Profile state: `captures/myts/profile/` = fresh run20 logged-in session;
pre-run20 session in `profile-backup-run20-20261013-213100/`.
Pcap: `captures/myts/run20.pcap` (root-owned, git-ignored). Parser kept only
in /tmp (throwaway); re-create from this section if needed
(SLL2 header = 20 B, then IPv4/TCP/TLS-ClientHello walk for ext type 0).

## run21 (2026-10-13): per-process attribution — DONE, login is 100% native

Tool: new log-only `LD_PRELOAD` shim `tools/myts/connwatch.c` (built to
`captures/myts/connwatch.so`, git-ignored) hooking `getaddrinfo` (hostnames)
+ `connect` (IPv4), tagging `main=1` (browser process, no `--type=`) vs
`main=0` (Chromium children). Zero redirect, login proceeds normally.
User logged out in the run20 client (back to login screen, no wipe), isolated
tree killed after environ-identity check (normal instance untouched),
relaunched with the shim (`run21-conn.log`), user logged in again.

Result (126 lines, login cohort fully inside):
- **All myTeamSpeak resolutions come from the main process:** 1×
  `www.myteamspeak.com`, 13× `clientapi.myteamspeak.com`, plus chat/push and
  `update.teamspeak.com` — every one `main=1` (PID 121190, the browser
  process). Each `clientapi` resolve is immediately followed by its connect:
  resolve→connect pairs, native RPC shape, not a page load.
- **The CEF NetworkService child (`--type=utility …NetworkService`) makes
  zero myTeamSpeak connections** — only Google/Chromium IPs and the files
  host. The `www` precursor is therefore also native code, not a CEF page.
- Non-blocking `errno=115` (EINPROGRESS) on the connects is normal.

**Verdict:** login is 100% native, and run14 already excluded the
Channel/cpp-httplib sender — so the login POST goes through the **second
native HTTP stack (Boost.Beast)**. Next: hook the Beast write/send site
during a fresh login (run6-style plaintext capture at the Beast layer),
which yields the real `login` RPC body + wire password framing (Q1) and,
one caller level up, the KDF (1D).

Profile state: `captures/myts/profile/` = fresh run21 logged-in session
(logout+login cycle). run20 pcap + run21 conn log retained under
`captures/myts/` (git-ignored).

## run22 (2026-10-13): Beast send path narrowed statically — login reply handlers found, capture staged

Static-only session (no launch/kill; live isolated tree PID 121190 + normal
instance verified via `/proc/<pid>/environ`, md5 `8234f961…` re-confirmed).
Eight headless runs on the existing Ghidra project (`-noanalysis`,
disposable scripts in `/tmp/opencode/`, repo kept clean):

- **Beast confirmed as the second native HTTP stack.** `boost::beast`
  `write_op`/`serializer`/`ssl_stream<basic_stream<asio::ip::tcp…>>` RTTI
  litters rodata (file `0x318xxx`); OpenSSL is **statically linked** (0 SSL
  entries in dynsyms, no `libssl` dlopen) so send sites can't be enumerated
  via imports — in-process gdb hooks only.
- **REST endpoint table found.** A constructor-range function around
  `0x1d8f030`–`0x1d8f700` builds 9+ URL `std::string`s into an object
  (`RBX+0x00…`): `/authentication`, `/session`, `/synchronization`, `/user`,
  `/addon`, `/integration`, `/messenger`, `/tschat` (all
  `https://clientapi.myteamspeak.com/…`, exact lengths verified from file
  bytes with the `link = file + 0x100000` slide). Tail calls client setup
  `0x1e330d0` with the table. (Caveat: the Ghidra slide was verified for
  LOAD0/rodata and `.text`; `.data.rel.ro` addresses need per-segment
  mapping — see below.)
- **Beast JSON reply callback reversed: `FUN_01dacba0 @ 0x1dacba0`.**
  Entry found by backward RET scan from the `"data json: "` log site
  (`0x1dad063`). Decompiled: async response handler, `status()` via vtable
  `+0x20`, `== 200` → JSON parse (`FUN_0295fcc0`/`0295fc30`), logs
  `"data json: <A> proto json: <B>"`, delivers to continuation at
  `RDI+0x30` slot `+0x30`; else `"http status code: "` / `"invalid
  response"` / `"empty response"`. So the account/sync lib speaks **JSON
  over Beast** on at least some endpoints (alongside the ts3cloud Channel).
  Note: no `"password"`/`"auth_token"` JSON key literals exist in the
  binary — the login JSON key names (if any) are still unknown.
- **40-entry handler table** (`{slot, 8, handler}` triples, file `0xb32c8`,
  git-ignored scratch): maps response slots (`.data.rel.ro`
  `0x3eff9a8…`, read back relocated via Ghidra memory) to sibling handlers
  (`0x1dacab0`, `0x1dacb20`, `0x1dacba0`, `0x1dada30…0x1dadea0`, plus shared
  `0x4005e50`/`0x4005e00` and `0x816xxx` entries). Our callback is index 2.
  Zero *recorded* code refs (expected under `-noanalysis`); the request
  (send) side binds these at runtime via vtable (`0x3eff9b8` DATA ref).
- **Bridge thread (KDF approach):** `getAccountHashedPassword` bridge id =
  `0x99` (153), registrar `0x1ab72f0` (disasm `0x1aa6d53…`, run15 shape
  confirmed). Invoke forwarder `FUN_01acf7b0` decompiled: generic
  continuation plumbing, not crypto — registrar path stays a sink, same as
  run7 verdict.
- **Staged, not yet run:** `tools/myts/gdb_beast.py` (new, compiles,
  `MYTS_DRY` preflight passes) = run6 trio + log-everything breakpoints on
  the handler block (`0x1dacab0…0x1dada90`, unknown ABI → dumps all six arg
  regs as attempted strings/vectors + timestamps). Plan: gdb-launch a
  **copy** of the isolated profile (`captures/myts/profile-run22/`,
  already `cp -a`'d, 171 MB — live profile + normal instance untouched, no
  wipe needed since logout+login replays the login flow per run21), user
  logs out + back in with the throwaway account; timing correlation picks
  the login handler, whose binder is the send site (one level down) and
  whose request builder is one level up toward the KDF.
- **Round 3 DONE (~21:55, fresh login in verified gdb client): 13 Channel
  RPCs again, still zero HANDLER hits across all 31 slots.** Login
  request+reply used none of: Channel POST, the 40-table handlers, the
  Channel parse site. Static corollaries nailed in parallel: exactly ONE
  code xref to `application/ts3cloud` in the whole binary (`0x1efd816`,
  Channel) — Beast uses different framing; `application/octet-stream` /
  `Content-Type: %s` refs are generic MIME/CEF tables, not the sender; the
  `www` literals belong to the uploader (`FUN_01c31af0`) and misc bridges,
  and all oauth/grant_type/form hits are vendored gRPC — www is a dead end
  for the login body. The framing-error string has a single user too
  (`FUN_01efd410`, Channel) — framing is descriptor-driven, so literal
  hunting is exhausted; method names come from descriptors at runtime.
- **Round 4 staged (`gdb_beast.py` + PARSE-ENTRY, `MYTS_RUN=run25`): stop
  hunting the sender statically, catch the REPLY globally.** New
  breakpoint at `ParseFromString` ENTRY (`0x289f050`, all stacks): saves
  every 64B–16KB parse buffer (cap 5000, offline net) and runs a
  dependency-free wire-shape match inline (`field1 bytes 40–80B +
  field 2 printable 30–64B` = `LoginSession{key,session}`; self-tested
  true-pos/neg). On a hit it logs lengths + `bt 25` — the backtrace IS the
  Beast reply path; request builder/KDF follow statically from that class.
  Needs: kill run24 gdb (verified), relaunch, user logs out+in (no wipe).
- **Round 4-bis DONE (~22:00, fresh login, gdb 148205): global parse trap
  caught the login TOKEN flow.** 105 parse dumps; offline wire-layout
  triage (field#/type/length only, no values) shows: 4× `152B =
  [(1,str:149B)]` token-textured (83%+ printable) parses at SEQ 8–11,
  BEFORE the first Channel REQ — crisp `AuthTokenReply` shape
  (`auth_token=1`, no field 2). Rest: badges mispairs (3756B), identity
  crypto (331/332B: 64/32/112/33B fields), encrypted sync blobs (my walker
  rejects = not protobuf at all — client trial-parses them, fails, treats
  as encrypted; independent confirmation of §7), token-ish 246/307B
  ambiguous. Crisp `LoginSession` (key~48 + session~36 + username) seen
  NOWHERE — its reply either uses another parse entry or arrives as JSON.
  `gdb_beast.py` matcher extended: `AUTH-REPLY` rule (f1 str 100–260B, no
  f2) self-tested precise on round-4 bins (152✓, 246/307/badges/ident
  correctly rejected). Round 5 = same trap, logout+login replay: the
  AUTH-REPLY backtrace IS the Beast reply path.
- **Round 5-bis HIT (run28, fresh login, gdb 153616): 4× AUTH-REPLY with
  full backtraces.** Same 152B/149B token shape, thread 84, 1 ms apart
  (one reply parsed through 4 tail-call-collapsed layers). Convergent
  spine: `0x1d460b0` (in `FUN_01d45e10`) ← `0x1d4bade` ← `0x1d1d7ae` ←
  `0x1d1c399` ← `0x1d1bbfd` ← `0x124623` ← `0x124111` ← `0x1cbb68e` ←
  thread start; three leaf variants above the dispatcher. Static caveat:
  0x1d4bade decompiles as a flock helper — function boundaries are
  unreliable under `-noanalysis`, so the follow-up used raw disasm
  windows, not decompiles (tail calls collapse frames; one retaddr even
  lands mid-NOP).
- **Round 6 staged (`MYTS_RUN=run29`): probe the dispatcher object.**
  New breakpoints at dispatcher ENTRY (`0x1d45e10`, dumps regs + handler
  object) and the post-parse point (`0x1d460b0`): each dumps
  `[this-0x40, this+0x340)` raw to `.bin` plus a metadata-only log line
  (offsets/lengths/short-hashes, never content) for every decodable
  string/vector, plus a stack window. The request context (URL, method,
  body, KDF-side continuation) should be reachable from that object.
  Needs: kill run28 gdb (verified), wipe copy (logged-in launches hand
  off — deterministic rule), relaunch, user fresh-logs-in.

## Session close-out (2026-10-13 ~22:15, user stopped for the night)

## run30 (2026-10-13 ~22:27): syscall-trap v1 — cap eaten by CEF/audio noise

Same fresh-profile gdb pattern (`MYTS_RUN=run30` + `SSLKEYLOGFILE`), new
`SendTrapBreakpoint` on libc `send`/`sendto`/`sendmsg` gated by
`/tmp/myts-sendgate` (cap 400). Gate opened at login screen, user logged in.

- **All 400 SEND hits fired within 0.4 s of gate-open, all noise:** main
  thread hammering fd 188 with 112 B `send` (bt: `libcef.so` IPC) and thread
  77 fd 127 (`pa_write`, pulseaudio). The real login POST (~4 s later, REQ
  burst at +4.4 s) was never recorded — cap exhausted.
- **Bonus: `SSLKEYLOGFILE` works** — client wrote TLS secrets from startup
  (`run30-keys.log` 5 KB; +778 B over the run). Unproven whether it covers
  the native Beast/OpenSSL stack or only CEF/BoringSSL — needs a pcap +
  decrypt attempt (round 32 material, needs sudo tcpdump + TLS parser).
- Fix for round 31 (in `gdb_beast.py`): bt taken first, hits whose bt
  contains `libcef.so`/`libpulse`/`libasound`/`hotkey_helper` dropped
  *uncounted*, cap raised to 5000. fd-watch extended with
  `/proc/net/tcp{,6}` snapshots for fd→inode→IP mapping.

## run29 (2026-10-13 ~22:20): round-6 dispatcher probe — AUTH-REPLY lead FALSIFIED

Killed run28 gdb (verified `MYTS_RUN=run28`+profile-run22 in both envs;
normal instance had meanwhile restarted itself as PID 167261 on the default
profile — untouched), wiped `profile-run22/{config,cache}`, relaunched
`MYTS_RUN=run29` with the dispatcher probe (`DISPATCH-ENTRY 0x1d45e10`,
`DISPATCH-PARSE 0x1d460b0` + full trio/PARSE-ENTRY/31 HANDLERs — 37 armed,
dry-run clean). Fresh profile stayed hooked (handoff rule holds, 4th
confirmation). User fresh-logged-in (~66 s after start, post-login sync
burst normal, first REQ already `requestServerItems`+valid session).

- **Zero `DISPATCH-ENTRY`/`DISPATCH-PARSE` hits, zero `HANDLER` hits (0/31),
  zero new `AUTH-REPLY`/`LOGIN-REPLY` at login time.** The Beast login
  request+reply remains fully unhooked from every trap.
- **The 4× 152B/149B "token" parses fired at STARTUP (+0.7 s), ~65 s BEFORE
  the login, on a fresh-wiped profile that holds no session.** Byte-identical
  (`cmp` clean, sha256 match) to run28's "login-time" token and across all 4
  parses within run29. Spine converges with run28 (`0x1d460b0 ← 0x1d4bade ←
  0x1d1d7ae ← …`, run29 just missing run28's tail-call leaf frames above the
  parse entry). `0x1d460b0` appears as a *return address* in the spine yet
  the breakpoint exactly there never fires — consistent with the run28
  caveat (tail-call-collapsed frames, retaddr landing mid-function on a
  branch that skips that exact instruction).
- **Verdict: the AUTH-REPLY trail (rounds 4–5bis) chased a startup constant,
  not the login token.** A session token cannot pre-exist its login on a
  wiped profile; the matcher (`f1 str 100–260B, no f2`) is matching some
  other baked-in single-field message (cert/key/signed blob) parsed 4×
  through collapsed layers at every startup. Retire the AUTH-REPLY matcher
  as a login signal; keep `ParseFromString`-ENTRY as a generic trap.
- Standing: login = native main-process traffic to `clientapi` (run20/21),
  Channel = post-login sync only, **both Beast send and Beast reply paths
  still unhooked**. The `/authentication` URL table (`0x1d8f030`–`0x1d8f700`)
  readers were never followed — best static lead left.
- **Next (round 7) options:** (A) `SSLKEYLOGFILE` cheap test — plain (non-gdb)
  launch with the env var, logout+login, check for a keylog file (iff the
  static OpenSSL honors it); (B) gdb `catch syscall sendmsg/write` during the
  login window with auto-bt — backtrace IS the Beast sender, then targeted
  plaintext breakpoints at the serializer; (C, static, no user needed) follow
  the `/authentication` table readers → send site → request builder → KDF;
  (D) `LD_PRELOAD` sendmsg+getpeername logger for a precise login-send timing
  map to guide (B). Recommend C now + A/B next login window.
- Live state: run29 gdb client (PID 167661 under gdb 167636) LEFT RUNNING,
  logged in, hooks live; normal instance (PID 167261, default profile)
  untouched. `profile/` (run21 session) intact; `profile-run22/` = fresh
  run29 logged-in session.

## run31 (2026-10-13 ~22:29): syscall-trap v2 — ARMED, awaiting login

Run30 killed (verified), profile-run22 wiped, `MYTS_RUN=run31` relaunched
with the v2 trap (noise filter + cap 5000) + `SSLKEYLOGFILE=run31-keys.log`.
Gate closed, fd-watch (fd + `/proc/net/tcp{,6}` snapshots) running. Same
choreography: user reports login screen → gate opens → user logs in.

## run31 results: login POST sends still absent

34 native SENDs, all accounted for, none the login: ~30× 20 B `sendto`
(DNS — proven: #001's bt is `sendto ← getaddrinfo` on thread 84, the
Channel/RPC thread, 0.3 s before the post-login sync burst; the migrating
fds/threads across the login window = the run21 resolve burst) + 4×
`sendmsg` fd 234 (rdx shown is `MSG_NOSIGNAL`, length unknown; main-binary
frames `0x58c8xxxx`, unrelated region — likely voice/crashpad, TBD).
**Zero TLS app-data-sized sends between gate-open and the REQ burst** —
the login POST used none of `send`/`sendto`/`sendmsg`, or its bt was
dropped by the libcef noise filter. Open: `write`/`writev`/`sendmmsg`
(unhooked), or sender inside browser-process libcef net (filtered).
Keylog at 17 entries, coverage still unproven (needs pcap + decrypt).

## run32 results (2026-10-13 ~22:35): sender path CAUGHT, client DoS'd by own traps

v3 (write/writev/sendmmsg + CEF split cap) captured the live TLS sender:
thread-84 `write` bursts on fresh fds (`sendmmsg vlen=2 → sendto 20B DNS →
`write 334/340 → 80 → 176-250 → 24`) = per-connection TLS handshake+POST,
right before the Channel REQ burst. Backtraces give real sender frames:
`write ← 0x7951779 ← 0x7945e26 ← 0x7944043 ← 0x7943ec7 ← …` (two upper
variants: `0x7941159…` vs `0x78fb23f…`) — static DumpAsm follow-up pending.
BUT the traps also machine-gunned the client: thread-58 `write fd=187
798B` background loop (bt `← 0x688ef38 ← 0x688ebe2 ← …`, pre-login,
unrelated) ate 4758/5000 native slots in 11 s; the all-stop storm stalled
TLS handshakes → server timeouts → `moveHome` retry loop (244×, unique to
run32 — run29/31 clean) = the user's "error in continuazione". Added
`0x688ef38` to the noise filter.

## run33/35 (2026-10-13 ~22:36-22:43): startup SIGABRT ×4 — diagnosed

Full-trap launches aborted deterministically at +0.6 s (`mutex lock
failed: Invalid argument`, thread 75/76, pre-parse). Plain launch (same
wiped profile) and minimal-script launch (run34, trio only) both survive —
ruling out environment/profile. Abort-bt hook (new `on_stop` SIGABRT →
`runXX-abort-bt.log`) showed only terminate frames (`← 0x59296316…`).
Root cause: the send/write trap STORM during startup (10k+ all-stop hits/s
while threads spawn) — run32 survived it once by scheduler luck. Fix (in
`gdb_beast.py`): send-traps planted DISABLED, enabled 60 s later via
`gdb.post_event` from a daemon thread (`MYTS_SEND_DELAY`, logged
"SENDTRAP opens in 60s"). run36 proves it: 0 aborts, startup parses normal.

## run38 (2026-10-13 ~23:07): decrypt path — BUILT, TESTED, VERDICT: DEAD FOR LOGIN

Plain launch (reliable, zero errors) + `SSLKEYLOGFILE` + user-run
`sudo tcpdump -i any tcp port 443` (22 MB, 28.6k pkts, 562 streams).
New tool `tools/myts/tls_decrypt.py` (pcap/SLL2 + TCP reassembly + SNI +
TLS-1.3 trial-decrypt with TRAFFIC_SECRET_0, metadata-only log):
selftested (RFC 5869 PRK, manual-vs-lib KDF cross-check, AES-GCM
round-trip, synthetic SNI) and debugged on the real capture — fixed 2
genuine bugs found along the way (pcap endian branches swapped;
HKDF-Expand-Label length field must be the OUTPUT length, caught only by
the cross-check since round-trips hide it).
Result: **0 streams decrypt** — including the small clean `dns.google`
DoH stream as control. `strings` settles it: the main binary has NO
`SSLKEYLOGFILE` support (only CEF/BoringSSL logs; the binary's keylog
strings are a gRPC-test stub + an "Ignoring TLS Key logging" error
template). The 7 logged conns are CEF contexts (DoH excluded) — **native
Beast/OpenSSL conns are never logged, so this path cannot yield the
login**. Retire; keep the tool (works, may serve CEF traffic later).

## TOMORROW (next session entry point)

Goal unchanged: login request body + wire-password framing (Q1) + KDF (1D).
1. **Primary: gdb REQPATH late-open round** — script ready
   (`gdb_beast.py`: REQPATH entries 0x239B7F0/0x2336600, planted disabled,
   open at +60 s with send-traps; CEF thread-1 IPC filter; loop filter;
   abort-bt hook). Needs ONE fresh login. If the +0.6 s SIGABRT streak
   persists, bisect by dropping the 31-HANDLER block first (biggest
   early-planted delta never isolated), then DISPATCH/PARSE-ENTRY.
2. **No-user parallel: static upward walk** — `FindCallers.java` on
   0x2336600/0x239B7F0 in `captures/myts/ghidra` (request builder above
   the state machine; upward tail-call gap noted — walk CALLERS, not
   callees). Needs no login, no window.
3. Reference: live sender spine `write ← 0x7951779 ← 0x7945e26 ←
   0x7944043 ← 0x7943ec7 ← 0x78fb23f ← … ← 0x732a5a5` (run36); cluster
   identified as static-OpenSSL TLS (SHA-256 compress @ FUN_023f10a0,
   EVP-digest plumbing, handshake state machine @ FUN_02336600).
   AUTH-REPLY matcher retired (startup constant). Keylog/pcap retired.
Live state: all gdb/headless dead; run38 plain killed (verified);
normal instance untouched; `profile/` (run21 session) intact;
`profile-run22/` = run38 logged-in session (stale, wipe next round).

## run37 (2026-10-13 ~22:53-23:05): abort streak — PIVOT to decrypt path

2/2 launches aborted at +0.6 s with the storm-guard config (REQPATH
planted-disabled). run37#2 ≡ run36 + two INERT disabled breakpoints, yet
run36 survived — the abort is not script-determined (the only delta, a
noise string + disabled bps, never executes pre-gate). Scorecard:
survivors run29/30/31/32/34/36/plain, aborters run33×3/35/37×2. Gdb path
now unreliable (5/6 aborts); stop burning logins on it.
PIVOT (decided): plain launch (proven reliable) + `SSLKEYLOGFILE` (proven:
run36 keylog holds 8–9 full TLS-1.3 secret sets incl. EARLY + EXPORTER) +
user-run `sudo tcpdump -i any tcp port 443` (run20 pattern) → offline
TLS-1.3 decrypt in Python (`cryptography` 50.0.1 present; no dpkt — hand-roll
pcap/SLL2 + record parsing, ~150 lines: reassemble TCP, SNI-filter
clientapi, trial-decrypt 0x17 records with TRAFFIC_SECRET_0-derived
key/iv, per-direction seq from 0). If native Beast conns are covered by the
keylog, this yields the login HTTP request+response plaintext directly —
same prize as the traps, zero client disturbance, zero error windows.
Needs: ONE plain fresh-login round (run38) with pcap. No gdb, no gate,
no choreography timing — user just logs in whenever.

## run36 (2026-10-13 ~22:46): storm-guard build — CLEAN LOGIN, sender spine live

Survived startup (0 aborts), user logged in with NO errors (storm-guard +
loop filter fix the run32 DoS). Thread-85 `write` bursts again on fresh
fds; a **597 B app-data write** (fd 198, mid-sync — likely the
`synchronizeItems` CONFIG push, not the login) gave the full 13-frame
sender spine: `write ← 0x7951779 ← 0x7945e26 ← 0x7944043 ← 0x7943ec7 ←
0x78fb23f ← 0x78fb154 ← 0x78f1495 ← 0x787826b ← 0x788b88b ← 0x788ba5d ←
0x731af6a ← 0x732a5a5`. Pre-REQ login bursts (fd 186 @+3.9 s, handshake
sizes only — the POST may itself be a ~300 B write: 334/250/176) still
unattributed byte-wise. fd numbers recycle per connection (fd 198 inode
changed across snapshots; fd 186/235 too short-lived to sample) —
consistent with Beast short-conns. CEF-SEND cap (300) again eaten in 1 s
by thread-1 IPC — added thread-1 IPC-size filter for next round.
Static follow-up LAUNCHED: `DumpAsm.java` retargeted at the 12 sender
frames (`run36-decompile.log`, background headless) → identify functions →
request builder → plaintext breakpoint next round.
Live state: run36 gdb client logged in, hooks live; normal instance
untouched.

## run32 (2026-10-13 ~22:35): send-trap v3 — ARMED, awaiting login

v3: +`write`/`writev`/`sendmmsg` traps; libcef frames no longer dropped but
logged under a separate 300-slot `CEF-SEND` cap (answers "browser-process
libcef?" without drowning natives); audio/hotkey still dropped. fd-watch
now snapshots `udp{,6}` too. Same gate choreography.

## Session close-out (2026-10-13 ~22:15, user stopped for the night)

- **Run28 gdb client (round 5-bis) LEFT RUNNING, logged in, hooks live**
  (verify via `/proc/<pid>/environ`: `MYTS_RUN=run28`,
  `XDG_CONFIG_HOME=…/profile-run22/config` before touching). Normal
  instance (`/usr/bin/teamspeak`, default profile) runs alongside. The
  original isolated tree (121190) was closed by the user; its on-disk
  profile (`captures/myts/profile/`, run21 session) is intact, never wiped.
- **Round 6 is STAGED but NOT RUN** (`gdb_beast.py` + dispatcher probe,
  `MYTS_DRY` passes): kill run28 gdb (verified) → wipe `profile-run22`
  (mandatory — logged-in launches hand off) → relaunch `MYTS_RUN=run29`
  → verify hooked → user fresh-logs-in. Then read
  `run29-*-obj.bin` (request context) + `AUTH-REPLY` bt flow as before.
- Standing results: login = 100% native main-process Beast traffic to
  `clientapi` (run20/21); Channel carries only post-login sync (runs
  6/14/22/24/26/28); token-reply path pinned with backtraces (run28);
  ts3cloud/framing-error literals are Channel-only; 40-entry handler
  table mapped; bridge id 153; KDF (1D) still open — request body +
  wire-password framing still uncaught (rounds 1–5bis).
- **Deterministic launch rule found (rounds 2/4/5 vs 1/3/4-bis): logged-in
  profile-run22 + gdb-launch = parent "exited normally" + unhooked twin
  survives; fresh-wiped profile-run22 = stays under gdb.** Three
  reproductions of the handoff (run23→133451, run25→145777, run27→151812,
  each PPID 7105, each on a logged-in copy). So logout+login replays are
  NOT capturable this way — every trap round must be a FRESH login
  (wipe copy, launch, user logs in). Round-4-bis proved fresh logins emit
  the 152B token parses, so the AUTH-REPLY trap will fire there.
- **Capture FAILED twice, zero hits (user-approved, 2026-10-13 ~21:47).**
  Attempt 1: gdb client exited normally instantly — the `cp -a`'d live
  profile carried Chromium `SingletonLock/Socket/Cookie`, single-instance
  trip. Attempt 2 (locks removed from the copy only): client aborted in
  early startup (`libc++abi: std::__1::system_error: mutex lock failed`,
  SIGABRT, coredump present) before any RPC thread ran — no REQ/HANDLER/
  PARSE fired. Live isolated tree (121190) + normal instance untouched.
  Prime suspect: copying a *live* Chromium profile mid-write (SQLite WAL)
  leaves inconsistent state. Fix staged for next round: fresh empty
  `profile-run22/{config,cache}` (copy is disposable; live profile intact)
  + identical gdb net — i.e. the run14/run20 wipe pattern, which worked.
- **Round 1 DONE with fresh profile (~21:50, user fresh-login, gdb
  131363): 13 Channel RPCs, login itself missed.** Fresh-profile client
  stayed up; user logged in by hand. `run22-*.bin` = textbook post-login
  sync burst, run14-shaped: first REQ already `requestServerItems` with
  zero-UUID `globalversion` + valid session, `sync_version: V1_1`
  everywhere, one CONFIG `synchronizeItems` push (encrypted blob), then
  integration/user/tschat pulls (same per-thread reply mis-pairing as
  run6 — some `.resp.bin` don't parse, don't trust those pairings).
  **Zero HANDLER hits** out of 9 hooked: the login request+reply used none
  of the hooked slots — it went through one of the ~31 other table entries
  (or a non-JSON Beast reply path). Next: `gdb_beast.py` widened to all 24
  `0x1daxxx` table handlers + `0x1332F30` + `0x816xxx` (arm failures now
  tolerated/skipped), relaunch, user logs out+in again in the new window.

## Tools (in `tools/myts/`, committed in `5492833`)

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
- `gdb_beast.py` — (new, uncommitted, run22) run6 trio + breakpoints on the
  Beast JSON-response handler block (`0x1dacab0…0x1dada90`); unknown ABI so
  every hit dumps all six arg regs as attempted strings/vectors with
  timestamps. Needs a logout+login drive in a gdb-launched copy-profile
  client; see the run22 section above.

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
