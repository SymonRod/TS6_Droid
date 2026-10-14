# myTeamSpeak login — run39 handoff (2026-10-14)

> **Superseded by [run40](myteamspeak-login-run40.md):** the password KDF is
> now demonstrated and standalone login succeeded. The target app is Flutter;
> run40 closed as research-only, with no application code changes.

> **Start here in the next session.** This round used the client supplied in
> `../teamspeak-client`, not the old `/opt/teamspeak` build. The earlier
> `myteamspeak-handoff.md` remains useful history, but its offsets and its
> separate-Beast-login conclusion must not be applied to this build.

## Outcome and remaining blocker

**The real `login` request was captured successfully.** The desktop client
logged in successfully using the credentials from `.env`, in an isolated
profile. The request goes through the native ProtobufRPC HTTP sender to:

```
POST https://clientapi.myteamspeak.com/authentication
body = u8 method_length + method_name + serialized LoginData
```

For `login`, the prefix is `05` followed by ASCII `login`. The password field
is **64 Base64 characters decoding to 48 bytes**. Its decoded value exactly
matches the desktop bridge's `getAccountHashedPassword` result.

**The plaintext-password → 48-byte transform is still unknown.** There is
no working standalone login implementation yet. No Android code was changed
this round; its existing lowercase SHA-512 hex encoding is not the observed
desktop encoding. Merely changing hex to Base64 will not solve it.

## 1. Build and environment

| Artifact | Size | MD5 |
|---|---:|---|
| `../teamspeak-client/TeamSpeak` | 79,757,920 B | `7eb9fdb89d3da783d3db55845c5066ca` |
| `../teamspeak-client/html/client_ui/main.js` | 10,786,018 B | `d5f22b19d42fea92c33d5d5a9fddc46d` |

- `/opt/teamspeak/TeamSpeak` and the old `captures/myts/ghidra` project are
  absent in this environment. Ghidra itself is also absent.
- Available: Python, gdb, objdump/readelf, Java, curl, tcpdump.
  No system protoc, compiler, xdotool or Xvfb was found.
- A disposable Python venv was created at `/tmp/opencode/myts-venv` with
  `capstone`, `pyelftools`, `protobuf`, `grpcio-tools`, `python-dotenv`,
  `requests` and `websocket-client`. These are tooling dependencies only;
  nothing was installed into the Android project or the system interpreter.
- **`kernel.yama.ptrace_scope = 0` here:** attaching to a running isolated
  client works. Do not assume the old notes' `ptrace_scope=1` restriction.
- Display variables were already set. The client starts normally.

### Address convention — important

All offsets in this document are **ELF virtual addresses relative to the PIE
load base**. They are not file offsets or Ghidra-rebased addresses.

This build's `.text` ELF address is its file offset **plus `0x1000`**;
`.rodata` has identical file offsets and ELF addresses. Other segments have
their own mapping. Never use the historical blanket `+0x100000` conversion.

`tools/myts/elf_probe.py` uses `.eh_frame_hdr` function starts to avoid the
old RET-scanning / guessed-function-boundary problems. Its direct CALL/JMP
search reports **candidates**, which must be checked against disassembly.

## 2. Authorization and credential handling

The user explicitly authorized launching a separate client profile and
logging in with `.env` credentials, without touching their normal profile or
changing account settings/passwords.

- `.env` contains `USERNAME` and `PASSWORD`; values were read into memory,
  never printed, passed in shell command arguments, or copied into docs.
- `.env` was initially untracked and **not ignored**. `.gitignore` now ignores
  `.env` and `.env.*` to prevent accidental commits.
- Raw requests, password reference bytes, debugger output and profiles are
  local under the already ignored `captures/` directory. Treat them as secrets.
- Login was driven over **loopback-only CDP on port 9223**. The listener was
  verified as `127.0.0.1`, not a public interface.
- Native login also performs normal account sync. We did not edit bookmarks,
  contacts, passwords or account settings manually.
- **At close-out the isolated process group was terminated after verifying
  its executable, profile environment and group ownership. The debug endpoint
  is closed.** No normal client was stopped, and no debugger is intentionally
  left attached. Do not reuse the old PID 46059.

## 3. Confirmed login evidence

### Desktop bridge

The UI exposes:

```javascript
tsclient_internal.loginAccount(email, password, otp, callback)
tsclient_internal.logoutAccount(callback)
tsclient_internal.getAccountHashedPassword(callback)
```

The current `main.js` confirms login callback enums:
`LoginOk=1`, `LoginOffline=2`, `LoginFailed=3`, `EmailPending=4`,
`SessionOk=5`, `Login2FARequired=6`.

Initial login and subsequent isolated logout/login replays all returned
**`code=1`**. Logout returned `code=0`. No OTP was supplied or requested in
these successful tests. No backup key was returned by the initial callback.
The actual `LoginSession` reply was **not captured/decoded** this round;
do not claim its protobuf error field was observed as 200.

`getAccountHashedPassword` returns a 64-character string. Strict Base64
decoding gives 48 bytes. Two getter reads were identical. The actual captured
login password was compared locally and decoded to the exact same bytes.

Offline comparisons against the known plaintext ruled out:

- SHA-512 truncated to its first or last 48 bytes;
- the final 32 bytes of the observed value being either SHA-512 half;
- the final 32 bytes being plain SHA-256(password).

These are negative comparisons, **not proof of AES, Ed25519, a salt layout or
any particular KDF**. Such a layout must still be demonstrated.

### Actual HTTP request

Source files (all sensitive, ignored):

```
captures/myts/run39/probe-http2/002-http-request-rsi.bin  # endpoint
captures/myts/run39/probe-http2/002-http-request-rcx.bin  # framed request
captures/myts/run39/probe-http2/actual-login-password.bin # Base64 reference
captures/myts/run39/wire-password.bin                   # decoded getter
captures/myts/run39/wire-password-2.bin                 # second getter
```

The complete framed request is **147 bytes**. Decoded `LoginData` fields:

| Field | Observed value or length |
|---|---|
| `email` (1) | 20 characters; content not documented |
| `password` (2) | 64 characters, strict Base64 → 48 bytes |
| `sync_version` (5) | **1 = V1_1** |
| `device_name` (9) | 47 characters; content not documented |

All other fields are absent, including OTP, device ID and recovery key.
`skipSession=false` and `origin=CLIENT` are proto3 defaults; absence is not
evidence of explicit setters on the desktop side.

Native sender disassembly establishes the `application/ts3cloud` content-type
argument. HTTP headers on the network were not separately captured.

Observed method order in the same targeted capture:

```
deleteSession                  # our explicit logout
login                          # the real login, before sync
requestServerItems
getIntegrationUserStatus
getSignedBadges
getActiveIdentifierList
synchronizeItems
getIntegrationUserStatus
getSignedBadges
getContactList
getSignedBadges
getAllowedIdentifierList
```

There was no observed `requestAuthToken` call in this captured replay.
Do not extrapolate that to every desktop authentication mode.

### Native sender breakpoint (live-confirmed)

Function: **`0x46d9130..0x46d9750`**, identified through the content-type
literal, then verified live. The literal starts at `0xec2c29`, but the LEA
references **`0xec2c28`**: the preceding byte `0x28` is the libc++ short-string
length marker for the 20-character content type. Searching only the first
ASCII character misses this reference.

```
0x46d9545  lea r8, [content_type_std_string]
0x46d954c  lea rdx, [rsp+0x20]
0x46d9551  mov rcx, rsp
0x46d9554  lea r9,  [rsp+0x40]
0x46d9559  call [rax+0x18]         # set request breakpoint here
```

At **`base + 0x46d9559`**:
`rsi = endpoint std::string*`, **`rcx = framed body std::string*`**,
`r8 = content-type std::string*`.

Live login request stack begins:

```
0x46d9559 ← 0x46d9038 ← 0x46d9890 ← 0x46d9b60
            ← 0x46dee00 ← 0x46de293 ← 0x4735fa8 …
```

This is an async worker stack, not a stack directly containing the KDF.
**For this build, login and subsequent sync share this sender.** The old
Beast-only-login theory is not an appropriate starting point now. Whether
older failures resulted from build changes, address conventions or another
cause was not established; do not retrospectively assert an explanation.

## 4. Static / dynamic crypto findings (not the login KDF yet)

Recovered RTTI and ELF relocation tables identify:

- `Encryption_Impl_V2` vtable at **`0x4a77d98`**;
- constructor **`0x2a81f80`**;
- string SHA-512 wrapper **`0x2a82110`**, calling raw helper
  **`0x47592b0`** with `(input_ptr, input_len, output_ptr)`;
- SHA-512 raw helper forwards to **`0x3c292f0`**; disassembly has a 128-byte
  block loop and SHA-512-sized output/state, not the earlier Ed25519 guess;
- assert-bearing wrapper **`0x2a7ffa0`** checks an intermediate is 64 bytes,
  then dispatches through encryption vtable slots;
- candidate encryption wrapper **`0x2a82c00`** constructs a 16-byte value and
  concatenates it with another result. **Not proven to produce login password.**

Late attach probes on a logout/login replay caught SHA-512 calls mainly over
32-byte inputs and sync-sized payloads (159, 233, 277, 319, … bytes).
The 32-byte inputs did not match plaintext, SHA-256(password), or either
SHA-512(password) half. They appear on account/sync decryption paths; no
captured SHA-512 input directly established the plaintext-password transform.

The candidate `account-getter` at `0x2a5a820`, `hash-wrapper` at `0x2a7ffa0`
and `encrypt-wrapper` probes did not yield the login KDF. Their tags in the
probe script are hypotheses, not recovered symbol names.

Important limitation: the hooked replays used a process that had **already
completed its first login before gdb attached**. Logout may retain derived
credential material. The absence of plaintext KDF hits during replays does
**not** establish which functions run on the first login in a fresh process.

## 5. Descriptors from the new binary

`docs/proto/extract_descriptors.py` was imported in the disposable venv and
its existing extractor parsed **67 descriptors** from the supplied build.
They were saved locally under:

```
captures/myts/build-7eb9fdb8/**/*.proto.descriptor.bin
```

These new descriptors were **not** rendered into committed `.proto` files or
round-trip verified with protoc. Existing committed schemas remain pinned to
the older build. Relevant additions visible in the new descriptors:

- `LoginData.recovery_key = 10` (`string`);
- `LoginSession.deletion_info = 17` (message);
- `remaining_recovery_keys = 18`, `recovery_keys_used_count = 19`,
  `remaining_recovery_keys_known = 20`, `recovery_key_count = 21`.

The original login fields/field numbers remain compatible with the actual
captured request. Dynamic decoding used `descriptor_pool.Default()` and
`message_factory.GetMessageClass()`, importing Google's `any_pb2`, etc. first
to register well-known dependencies. Trying a blank pool without `Any`
registration failed; it is a tooling dependency issue, not bad descriptors.

## 6. New tools and their tested status

All are uncommitted working-tree additions:

- **`tools/myts/elf_probe.py`**: read-only string LEA xrefs, direct caller
  candidates and function disassembly using ELF unwind boundaries. Used
  successfully throughout this round. Example:
  ```bash
  /tmp/opencode/myts-venv/bin/python tools/myts/elf_probe.py \
    ../teamspeak-client/TeamSpeak --function 0x46d9130
  ```
- **`tools/myts/gdb_login_probe.py`**: attaches only to a PID whose executable
  matches the supplied build and whose `XDG_CONFIG_HOME` is under this repo's
  `captures/`. Checks MD5, records metadata-only stacks and writes sensitive
  string/raw-SHA512 inputs locally. This captured the real login successfully.
  `MYTS_DRY=1` preflight and Python compilation pass.
- **`tools/myts/desktop_login.py`**: reads `.env` in memory, drives isolated
  logout/login/getter over localhost CDP, optionally attaches the probe first.
  The login-driving and capture orchestration worked. See shutdown caveat below.

### Debugger shutdown caveat

The original 45-second Python `threading.Timer → gdb.post_event(detach)`
occasionally worked but **hung after the successful HTTP capture**;
`desktop_login.py` timed out waiting for gdb and terminated **its own debugger**.
The client survived; the capture was already complete.

The tools were subsequently changed to have the parent send **SIGINT to gdb**
after the bridge calls, allowing `continue` to unwind into `finally: detach`.
They no longer rely on the timer. **This final SIGINT shutdown change was only
compile/dry-run checked, not exercised in another live round**, because the
user requested a handoff. Verify it first next time; do not report it as a
proven cleanup solution yet. Direct standalone probe use now requires
interrupting the debugger to detach.

All three files pass `python3 -m py_compile`. No app build/tests were run,
since no app code was modified.

## 7. Local state at session end

- `captures/myts/run39/{config,cache,data}`: authenticated research profile,
  retained on disk; do not commit or erase it.
- Its `config/TeamSpeak/Default/settings.db` has `AccountData` and
  `ProtobufItems` tables. Only table/key metadata was inspected, not decoded
  account records. WAL-aware read-only access is necessary if inspected live.
- `run39/probe`: getter-only targeted attach, no candidate getter hits.
- `run39/probe-login`: crypto probes during an isolated replay.
- `run39/probe-http`: empty HTTP attempt; its 45-second window expired before
  the actual replay. Do not use it as evidence of a different sender.
- **`run39/probe-http2`**: successful real-login HTTP capture, metadata stacks,
  sync traffic and crypto input samples. This is the primary evidence folder.
- `run39/client.log` / debugger logs may contain sensitive client output.
  Never print them wholesale; inspect locally and summarize metadata only.
- Process and localhost debug endpoint are **closed**.
- Working-tree edits: `.gitignore` and the three new tools, plus these docs.
  No commits were created and no existing user changes were reverted.

## 8. Recommended next round — first-login capture, then forward trace

**Goal:** identify the plaintext-password transform, not rediscover the sender.

1. Reconfirm binary MD5 and permissions. Ask before launching/using account
   credentials again. Do not use the old `/opt` scripts or their offsets.
2. Create a **new** research directory, e.g. `captures/myts/run40`, with fresh
   `config/cache/data`. **Do not wipe run39** or copy a live Chromium profile.
   Launch the supplied client with those three XDG variables and a free,
   loopback-only CDP port. Do not start logged in from run39's cached profile.
3. Let startup settle, then attach the small targeted gdb probe to that exact
   isolated main PID. Since ptrace is allowed here, no gdb-under-startup storm
   is necessary. Verify its ready log before triggering the first login.
4. Drive **one first login** with `.env`, without printing credentials. The
   existing `desktop_login.py --probe` can drive it; its logout call on a
   fresh empty profile should be checked, or omitted for this specific case.
   Use a new probe output directory; the script refuses stale metadata files.
5. Keep **`base+0x46d9559`** as the ground-truth request hook. Confirm `login`
   and compare its password with the run39 reference locally. Capture the
   first-login SHA-512 inputs/stacks before deciding whether the current
   crypto anchors are relevant. A cached replay's negative result is insufficient.
6. If there is no plaintext-to-output path in those hits, follow the **current
   `LoginData` request construction/password setter upstream of enqueueing**.
   Locate its native requester/bridge implementation using this build's
   descriptors, relocation/vtable data and exact unwind functions. The worker
   stack loses the producer because it is async; walking its TLS callees will
   not identify the KDF. Avoid another generic-assert/registrar sink.
7. If necessary, probe a likely derivation function with **known input and
   output reference comparisons**, not arbitrary memory-wide watchpoints.
   Add SHA-256/other primitives only after locating their real call sites and
   register ABI. Do not brute-force many password encodings against the account.
8. Once the exact transform is demonstrated, implement an **offline golden
   vector test with synthetic credentials**, then perform at most one paced
   standalone `/authentication login` validation. Only then change Android's
   password encoder, remove its temporary multi-encoding diagnostic, and set
   its observed login `sync_version` to `V1_1` with tests.
9. Decode the successful `LoginSession` reply next, to confirm session/key/
   renewal fields. Token renewal and sync decryption remain separate open work;
   do not assume solving login also decrypts bookmarks.
10. Close only the new research process/debugger, verify its debug port is
    closed, retain ignored evidence and update this handoff.

**Stop criteria for this round:** a demonstrated plaintext→wire-password
algorithm plus a successful standalone login, or a precise producer function
with captured input/output and enough evidence to reproduce it offline.
Do not spend another round on TLS interception, SSLKEYLOGFILE, broad syscall
traps or the separate-Beast-login hypothesis: the real sender is now known.
