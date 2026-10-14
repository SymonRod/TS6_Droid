# myTeamSpeak login — run40 handoff (2026-10-14)

> **Start here next time. The login password derivation is solved and a
> standalone login succeeded.** The target app is **Flutter**, not the legacy
> Kotlin app. The owner chose **research handoff only** for this round after
> confirming that Flutter's myTeamSpeak module has not been implemented yet.
> No application source changes remain from this round.

For the durable app-facing specification, including wire goldens, errors,
security constraints and current-build fields, read
**[myteamspeak-login-protocol.md](myteamspeak-login-protocol.md)**.

## Outcome

- Demonstrated the plaintext → wire-password algorithm with native input,
  salt, raw KDF output and Base64 output comparisons.
- Python standalone `POST /authentication` with method `login` returned
  **HTTP 200, `LoginSession.error = 200 = ERROR_LOGIN_OK`**, and a session.
- Deleted **only that standalone session**: HTTP 200,
  `LoginStatus.error = 204 = ERROR_SESSION_DELETED_OK`.
- Decoded the successful standalone `LoginSession` with this build's extracted
  descriptors. Token renewal and sync decryption remain open work.
- Research clients and loopback CDP ports are closed; ignored evidence remains.
- Stop criterion from run39 has been met. No further password-encoding trials
  or account logins are needed to establish the KDF.

## 1. Exact login derivation

For the desktop's byte-wise email normalization (ASCII lowercasing in the
Python reproduction):

```python
password_bytes = password.encode("utf-8")
email_bytes = email.encode("utf-8").lower()
salt = email_bytes + b"ts3Login" + password_bytes
derived = hashlib.pbkdf2_hmac("sha512", password_bytes, salt, 10_000, 48)
wire_password = base64.b64encode(derived).decode("ascii")
```

- HMAC **SHA-512**, **10,000** PBKDF2 iterations, **48-byte** derived key.
- Standard Base64, 64 characters, no newline; 48 bytes need no `=` padding.
- The password participates **twice**: as PBKDF2 password and as the final
  part of the salt. There is no delimiter around `ts3Login`.
- Do **not** trim, lowercase or otherwise normalize the password.
- The native email helper iterates individual bytes and calls
  `std::ctype<char>::tolower`, not Unicode string case folding. Captured
  account credentials were ASCII. Non-ASCII email behavior has not been
  validated against a real desktop account; do not silently substitute a
  language-sensitive Unicode lowercasing operation.
- This is **not** Base64(SHA-512(password)), truncated SHA-512, or a random
  salt concatenated with a hash. The previous Kotlin encoder is wrong.

Implementation: `tools/myts/password.py`. Five synthetic offline goldens in
`tools/myts/test_password.py` cover ASCII email case, a short ASCII vector, a UTF-8 password,
password whitespace and an empty password. The non-ASCII password test is a
Python synthetic vector, not a desktop-account or Android-provider test.

### Synthetic reference vector (safe to commit)

```text
email:     Alice@EXAMPLE.COM
password:  correct horse battery staple
wire:      rn8XzshqPQxIb7jPVZNLnVQrIpD42wx3qeo6uKVh7naW8LiH0ZEEtgUOA+4TZlIw
```

This vector was calculated offline with Python hashlib. The real account's
password/hash/reference bytes are **not** in documentation or tests.

## 2. Build and recovered producer path

Same binary as run39:

```text
../teamspeak-client/TeamSpeak
MD5 7eb9fdb89d3da783d3db55845c5066ca
```

All addresses are **ELF virtual addresses relative to the PIE load base**.
Use `tools/myts/elf_probe.py` and unwind boundaries, not historical `/opt`
offsets. The ground-truth HTTP request hook is still `base + 0x46d9559`.

The first fresh-profile login exposed a **producer-side synchronous stack**:

```text
0x46d9559 ← 0x46d9038 ← 0x46daa34 ← 0x46db59c
  ← 0x2a23412 ← 0x2a23ee7 ← 0x2518bf8 …
```

This was the useful difference from run39's async-worker stack. Static
inspection followed the request/password setter upstream, as planned:

| Function/call | Address | Demonstrated role |
|---|---|---|
| Account login producer | `0x2a238a0..0x2a24080` | Copies email/password, derives login and encryption values, then builds login |
| Login KDF call | `0x2a23bbe` | Calls `0x2a7fc70` |
| Login derivation | `0x2a7fc70..0x2a7fde0` | Lowercase email + `ts3Login` + password, PBKDF2 → Base64 |
| Byte-wise email lowercase | `0x2a7f780..0x2a7f8a0` | `std::ctype<char>` per-byte lowercase |
| 48-byte KDF wrapper | `0x2a81930` | Sets output length `0x30` |
| PBKDF2 string wrapper | `0x2a83320..0x2a83440` | Password/salt strings, output length and iteration count |
| Raw PBKDF2 helper | `0x47594a0` | Digest selection 8, then PBKDF2 implementation |
| Base64 wrapper | `0x2a81970` → `0x25421e0` | Encodes the derived bytes |
| Login request constructor | `0x2a220b0..0x2a238a0` | Password field copied at `0x2a22f91`; sets sync version 1 |

Login derivation ABI at entry: hidden result string pointer `rdi`, password
`std::string*` in `rsi`, email `std::string*` in `rdx`.

PBKDF2 string wrapper ABI: hidden result `rdi`, password `rsi`, salt `rdx`,
output bytes `ecx`, iterations `r8d`. These parameters and returned strings
were captured with entry and GDB finish breakpoints.

### Encryption derivation — useful next anchor, not a completed sync decoder

The same producer also calls `0x2a7fe30` at `0x2a23d5c`. Native input/output
comparisons demonstrate:

```python
encryption_value = hashlib.pbkdf2_hmac(
    "sha512", password_bytes,
    email_bytes + b"ts3Encryption" + password_bytes,
    10_000, 32,
)
```

This returns **32 raw bytes**, not Base64. They are passed into account state
via `0x2a72a70`. This solves that producer derivation only; it does **not**
establish the wrapping format of `LoginSession.key` or decrypt any bookmark.
Do not equate the 61-byte server `key` with a plaintext 32-byte AES key.

## 3. Evidence and live tests

The owner authorized a new isolated client profile and `.env` credentials.
No normal profile, bookmarks, contacts, passwords or account settings were
manually changed. Native login may perform its usual account sync.

All sensitive files below are ignored under `captures/`; never print or
commit them. Credentials were read into memory, not passed in shell arguments.

### Fresh-profile first login

`captures/myts/run40/{config,cache,data}` with loopback CDP 9224.
`probe-first-login/` captured the 147-byte login, password Base64 → 48 bytes,
sync version 1, identical to run39's password reference. Bridge returned
`code=1`. SHA-512 anchors still saw only 32-byte inputs after the request,
not the plaintext password; that negative result did not identify the KDF.

SIGINT debugger shutdown worked live: gdb exited 0 and `TracerPid` was 0.

### Targeted producer capture

A second fresh profile was retained at
`captures/myts/run40/fresh-derivation/{config,cache,data}`, loopback CDP 9225.
The successful, fixed targeted replay is:

```text
captures/myts/run40/probe-derivation-fixed/
  002-derive-login-rsi.bin          # plaintext password (secret)
  002-derive-login-rdx.bin          # account email
  002-derive-login-result.bin       # Base64 wire password (secret)
  003-pbkdf2-strings-rsi.bin        # password
  003-pbkdf2-strings-rdx.bin        # exact login salt
  003-pbkdf2-strings-result.bin     # 48-byte PBKDF2 output
  004-derive-encryption-result.bin # 32-byte encryption derivation
  005-pbkdf2-strings-rdx.bin        # exact encryption salt
  006-http-request-rcx.bin          # actual framed login
  metadata.log                    # lengths, parameters and stacks only
```

Local assertions compared these inputs and outputs with `.env`, the derived
algorithm and the run39 reference. **Every comparison matched.** The native
login again returned `code=1`, and gdb exited 0 without probe exceptions.

Two earlier new-probe attempts (`probe-derivation/`,
`probe-fresh-derivation/`) are **not valid derivation evidence**: the initial
finish breakpoint used reserved GDB attribute `number`, raising
`AttributeError`. Fixed to `capture_number`, then verified live above.
GDB can exit 0 despite a Python breakpoint exception; the driver now checks
its local log for Python exceptions too (that extra driver check has only
been compile-checked, not tested with another account replay).

### Standalone login — one attempt, no retries

`tools/myts/standalone_login.py` uses the offline derivation and dynamically
loads run39's new-build descriptors. It locally verifies its password against
the captured native derivation before making the request.

```text
POST https://clientapi.myteamspeak.com/authentication
Content-Type: application/ts3cloud
body: 05 + "login" + LoginData
LoginData: email, derived password, sync_version=1, research device_name
```

OTP, device ID, renewal token and recovery key were absent; skipSession and
origin were proto3 defaults. The reply was **1101 bytes**, bare protobuf.
Evidence: `captures/myts/run40/standalone/{login,deleteSession}-{request,reply}.bin`
and metadata-only `metadata.txt`.

Observed `LoginSession`:

- `error=200`, non-empty session (36 characters) and UUID (36 characters);
- `key`: **61 bytes**, purge nonzero, username, limits, myTS identity data,
  user certificate, push token and permissions present;
- `recovery_key_count` present in this build's schema;
- **`alternative_login_info` absent**: no renewal token, OTP renewal token
  or device ID returned for this no-device-ID request.

The new descriptor also adds `ErrorCommon` recovery errors 212
(`ERROR_2FA_RECOVERY_KEY_INVALID`) and 213 (`ERROR_2FA_NO_RECOVERY_KEYS`);
these are schema findings, not observed recovery-mode responses.

Do not assume the current Kotlin session store's renewal fields will always
be populated. Testing a device-ID/OTP mode and implementing renewal are
separate follow-up tasks; no such extra account requests were made here.

## 4. Repository and tooling state

- No commits created; pre-existing user changes retained.
- Added `password.py`, synthetic tests and `standalone_login.py`; extended
  `gdb_login_probe.py` with demonstrated producer/finish hooks.
- `desktop_login.py --first-login` skips logout and waits for the probe's
  ready marker, not merely log-file existence. Executable/profile validation
  remains in place.
- Five Python golden tests pass:
  `python3 -m unittest discover -s tools/myts -p test_password.py`.
- Research Python files pass `py_compile`; `git diff --check` passes.
- The new-build descriptors remain local and have not been regenerated into
  committed `.proto` schemas.
- An initial implementation targeted Kotlin by mistake. Those changes were
  removed **only from files changed by this round** after the owner clarified
  that Flutter is the target. The owner then chose research-only close-out.
  No Kotlin or Flutter application changes remain.
- Kotlin Gradle tests could not run: Android SDK absent. A temporary JVM-only
  harness also lacked `javac`; it is not app-validation evidence. No Flutter
  SDK, Dart executable or `../tslib` checkout is available in this environment.
- Final `/proc` checks found **no run40-profile processes**, and neither CDP
  port 9224 nor 9225 listening. Research processes had already ended when
  final shutdown checks ran; their exit cause was not investigated. No normal
  client was stopped. Profiles and captures are retained, not erased.

## 5. Next round — Flutter implementation, or sync research

For **Flutter login**:

1. `flutter/` currently has **no myTeamSpeak module or login screen**. Phase 6
   is not started; don't confuse the existing Kotlin feature with Flutter.
2. Start from `docs/flutter-migration-plan.md`; decide a Dart port versus the
   plan's preferred shared Rust implementation in `tslib`, once its checkout
   and Flutter/Rust toolchains are available.
3. Implement the demonstrated encoder with synthetic golden tests, exact
   protobuf framing, `sync_version=V1_1`, no diagnostic multi-encoding probes,
   no automatic account-login retries, and OTP/error handling.
4. Add a Flutter login screen, Riverpod session state and secure token storage;
   don't put session tokens in ordinary `shared_preferences`.
5. Treat missing renewal fields as a real observed case. Session expiry/OTP
   and server-side logout need explicit handling; sync is not required for M1.
6. Test offline first, then ask for authorization before another real-account
   login or device test. This round proved Python standalone login, **not** a
   login from the Flutter app on a phone.

For **sync decryption research**:

1. Start with the captured 32-byte `ts3Encryption` derivation and the 61-byte
   `LoginSession.key` above, tracing the account unwrap rather than guessing.
2. Follow the native setter/account decoder to establish key format, cipher,
   IV/nonce and authentication handling with input/output captures.
3. Produce a synthetic offline decrypt/round-trip test before importing any
   remote bookmark/contact data. Token renewal is another independent task.

Keep run39 as historical request-capture evidence. Do not repeat TLS
interception, the old Beast-only-login hypothesis or password-encoding guesses.
