# myTeamSpeak login — implementation reference

**Status: password login demonstrated end to end (2026-10-14, runs 39–40).**
This is the durable protocol/implementation reference, not a session log.
The Flutter app now has an M1 password-login Dart port
(`flutter/lib/src/myts/`, `flutter/lib/src/ui/myts_login_screen.dart`,
`flutter/test/myts_*_test.dart`); the legacy Kotlin code is **not** a
correct encoder to port. No app code was changed in run40.

Related documents:

- [run40 handoff](myteamspeak-login-run40.md): local evidence, tooling state,
  cleanup, next work;
- [run39 handoff](myteamspeak-login-run39.md): original real-login request
  capture and build/address conventions;
- [sync reference](myteamspeak-sync-protocol.md): other services, sync envelopes
  and encrypted item payloads;
- [Flutter migration plan](flutter-migration-plan.md): app architecture and
  phase 6; [schemas](proto/README.md): committed descriptor provenance.

## 1. What is proven, and what is not

| Finding | Evidence | Confidence/scope |
|---|---|---|
| `login` uses `/authentication`, ordinary ProtobufRPC framing | Native real-login requests, then standalone HTTP request | Live-confirmed |
| Password is the KDF in §2, not a SHA-512 hex digest | Native plaintext input, constructed salt, PBKDF2 parameters/output, Base64 output, wire/getter comparisons | Demonstrated for captured account; standalone server accepted it |
| Login sends `sync_version=1` (`V1_1`) | Native request and standalone request | Live-confirmed |
| HTTP 200 reply is a bare `LoginSession`; success code is 200 | Successful standalone reply decoded with current-build descriptors | Live-confirmed |
| The session can be deleted using `deleteSession` | Standalone deletion of its own session returned protobuf 204 | Live-confirmed |
| A distinct 32-byte encryption derivation exists | Native producer input/output plus offline match | Demonstrated; **not** a sync decryptor |
| OTP, recovery-key and renewal fields exist | Embedded protobuf descriptors, bridge callback enum | Schema-confirmed, **not live-tested** in those modes |
| Non-ASCII password goldens match Python's UTF-8 implementation | Synthetic offline tests | No real desktop/phone test with such a password |
| Flutter login, secure persistence and device behavior work | — | **Implemented as a Dart port (offline tests only); live phone login, OTP and renewal still untested** |
| Account-key wrapping, bookmark decryption, token renewal work | — | **Unresolved** |

Reference binary: `../teamspeak-client/TeamSpeak`, **79,757,920 bytes**, MD5
`7eb9fdb89d3da783d3db55845c5066ca`. Native addresses in §10 refer only to this
build and are ELF virtual addresses relative to its PIE load base.

The committed `.proto` files were recovered and round-trip verified from an
**older** build. Run39 extracted **67 descriptors** from this newer build into
ignored local captures, and run40 used the new descriptors to decode replies.
They have not yet been rendered/round-trip verified as replacement committed
schemas. Keep that distinction when generating Flutter or Rust bindings.

## 2. Password derivation — exact interoperable algorithm

Let `P` be the password's UTF-8 bytes and `E` the desktop's lowercased email
bytes. Compute:

```text
salt = E || ASCII("ts3Login") || P
DK   = PBKDF2-HMAC-SHA512(password=P, salt=salt, iterations=10000, dkLen=48)
wire_password = standard_Base64(DK)
```

`||` means byte concatenation: **no separators**, no terminating NUL, no
length prefix. The exact ASCII label is **`ts3Login`**, including case.

### Canonical offline reproduction

```python
import base64
import hashlib

def login_password(email: str, password: str) -> str:
    p = password.encode("utf-8")
    e = email.encode("utf-8").lower()  # ASCII-only byte lowercase
    salt = e + b"ts3Login" + p
    dk = hashlib.pbkdf2_hmac("sha512", p, salt, 10_000, 48)
    return base64.b64encode(dk).decode("ascii")
```

Same implementation: `tools/myts/password.py`. It makes **no network call**.

### Normalization and encoding rules

1. **Password is case- and whitespace-sensitive.** Do not trim it, normalize
   Unicode, lowercase it, hash it before PBKDF2, or convert its bytes to hex.
2. The desktop email helper lowercases **individual bytes** using a
   `std::ctype<char>` locale facet. For the ASCII account tested, the exact
   salt matches UTF-8 email bytes with `A..Z` converted to `a..z`.
3. Use locale-independent **ASCII** case conversion for that demonstrated
   behavior. Do not let a Turkish device locale turn `I` into dotless `ı`,
   and do not replace it with full Unicode case folding.
4. Non-ASCII **email** behavior of the desktop locale facet has not been
   tested live. The Python byte-lowercase implementation leaves non-ASCII
   UTF-8 bytes unchanged. Treat internationalized-email behavior as an
   explicit compatibility question, not as evidence of Unicode folding.
5. If the UI trims an email address, use the **same trimmed address** as both
   the request's `email` and the KDF's email input. Do not derive from one
   address and send another. Captures do not establish a special whitespace
   rule for email.
6. Both `P` and `salt` are **bytes**. A library taking UTF-16 code units or
   an implicit platform charset can silently produce the wrong result.
   Explicit UTF-8 is required for the reproduction and its synthetic goldens.

### PBKDF2/Base64 parameters that must not drift

| Parameter | Required value |
|---|---|
| PRF | HMAC-SHA512 |
| Iterations | 10,000 (not 1,000, not a tunable app preference) |
| Derived length | 48 **bytes** = 384 bits |
| Password argument | Raw `P`, **not** SHA-512(P) |
| Salt | Lowercased-email bytes + `ts3Login` + raw `P` |
| Text encoding of derived bytes | Standard Base64 alphabet (`+`, `/`), not URL-safe Base64 |
| Base64 wrapping | No whitespace/newline |
| Wire string length | 64 ASCII characters; 48 bytes require no `=` padding |

PBKDF2 produces a 64-byte first block with HMAC-SHA512, and `dkLen=48`
selects its first 48 bytes. This is **not** the first 48 bytes of plain
SHA-512(password). If implementing PBKDF2 itself, its block counter is the
standard four-byte **big-endian** `00 00 00 01`, and the block is
`U1 XOR ... XOR U10000`; preferably use a tested cryptographic library.

The KDF is deterministic for the same email/password. There is no generated
per-login salt, no decoded server salt to prepend, and no demonstrated AES,
Ed25519 or SRP operation in this password-to-wire transform.

## 3. Offline golden vectors (synthetic, safe to commit)

These are **not account credentials**. Calculate and compare locally before
any real-account test. The Python test file is
`tools/myts/test_password.py`.

| Email input | Password input | Expected Base64 |
|---|---|---|
| `Alice@EXAMPLE.COM` | `correct horse battery staple` | `rn8XzshqPQxIb7jPVZNLnVQrIpD42wx3qeo6uKVh7naW8LiH0ZEEtgUOA+4TZlIw` |
| `a@b` | `pw` | `jj4pMIxs3fEOw+NaR3mKjAY3hjGWUkBjkdvAzdLVa8X3G1XYWQ8gnz13hTOilOsi` |
| `I@EXAMPLE.COM` | `päss🔑` | `DyeSsvb4vLhbiBtn1NU+pj6EoR74H0A+xuNPWBWNo5EPUotPWEPyiCMI7jS93UUC` |
| `alice@example.com` | ` password ` (spaces included) | `xgFgM9ArJRO+1hxCKGDaavzAmtO/gHwKNJEgCv/18DnWS2M4dWr0XJ3wZDZmlGXA` |
| `a@b` | empty string | `T5Ir2MZzYi7mdaVfjcMGo+Hbftrj5XZvGChm9YfkT05k4ZzTbWW1rByv8xpa+CKU` |

For the first vector:

```text
salt ASCII: alice@example.comts3Logincorrect horse battery staple
salt length: 53 bytes
derived bytes (hex, 48 bytes):
ae7f17cec86a3d0c486fb8cf55934b9d542b2290f8db0c77a9ea3ab8a561ee769
6f0b887d19104b6050e03ee13665230
```

`alice@example.com` and `Alice@EXAMPLE.COM` must give the same result. Removing
spaces from the fourth password must give a **different** result. An empty
password vector tests encoding behavior only, not whether the server accepts
empty account passwords.

## 4. HTTP and RPC framing

```http
POST https://clientapi.myteamspeak.com/authentication
Content-Type: application/ts3cloud
```

Request bytes:

```text
u8 method_name_byte_length || ASCII(method_name) || serialized_request_protobuf
```

For `login`, the first six bytes are:

```text
05 6c 6f 67 69 6e    # 05 + "login"
```

- Use the **simple method name** `login`, not a full service/package name.
- There is no JSON envelope, gRPC five-byte header, delimited-message prefix,
  HTTP Basic auth, or service identifier in the body.
- The service is selected by the `/authentication` URL path, not `/login`
  or the historically ambiguous `/session` endpoint.
- The recovered RPC framing rejects method names of 128 bytes or more; the
  app should reject empty names too. All methods discussed here are ASCII.
- HTTP **200** carries the **bare reply protobuf**, without a method prefix
  or envelope. Application success/failure is inside that protobuf.
- Non-200 HTTP status and malformed protobuf are different failures from an
  application error. Do not parse an HTML gateway response as `LoginSession`.
- `application/ts3cloud` is the exact media type; do not append a charset.
- The standalone validation sent `User-Agent: cpp-httplib/0.11.1`, which also
  appears in historical forum captures. Run39 established the native
  content-type argument, **not a new-build capture of every HTTP header**.
  Neither that User-Agent's necessity nor a different User-Agent was tested.
- Use normal TLS certificate validation. No interception, custom CA,
  `SSLKEYLOGFILE` or disabled verification is required.

## 5. `LoginData` request — field numbers and observed behavior

Package: `com.teamspeak.myteamspeak.proto`; RPC service:
`com.teamspeak.myteamspeak.proto.login.LoginService`.

| # | Field | Protobuf type | Native run39/run40 observation / guidance |
|---|---|---|---|
| 1 | `email` | string | Account address, 20 characters in capture; original content kept private |
| 2 | `password` | string | The **64-character Base64 KDF output**, not plaintext |
| 3 | `skipSession` | bool | Absent/default false: a session was created |
| 4 | `origin` | enum `LoginOrigin` | Absent/default `CLIENT=0`; `WEBSITE=1` exists |
| 5 | `sync_version` | enum `Sync_Version` | **Present, `V1_1=1`**; `DEFAULT=0` is not the observed login value |
| 6 | `otp` | string | Absent in tested login; descriptor supports the OTP step |
| 7 | `device_id` | string | Absent in tested login |
| 8 | `otp_renewal_token` | string | Absent in tested login |
| 9 | `device_name` | string | Present; 47 characters in native capture, research name in standalone |
| 10 | `recovery_key` | string | New-build schema addition; **not used/tested** |

This is proto3. Absent scalars decode to defaults. Absence of `skipSession`
or `origin` does **not** prove the native code never calls a setter; it only
describes the serialized request. Empty optional strings need not be emitted.
There is no demonstrated requirement to invent a device ID for a basic
password login: successful native and standalone requests omitted it.
Device-linked renewal/OTP behavior needs a separate test before being claimed.

### Minimal demonstrated request

```text
email = address used as the KDF input
password = login_password(email, plaintext_password)
sync_version = V1_1 (1)
device_name = app/research device description
skipSession = false (default)
origin = CLIENT (default)
```

The actual native framed login was **147 bytes**. The standalone framed login
was **122 bytes** because the device description was shorter. Total length is
not a protocol constant; it depends on string lengths.

### Fully synthetic framing golden

For the first KDF vector, `device_name="TS6 Droid test"`, sync version 1 and
all other fields absent/default, the framed request is **109 bytes**:

```text
05 6c6f67696e
0a11 416c696365404558414d504c452e434f4d
1240 726e38587a7368715051784962376a50565a4e4c6e5651724970443432777833
     71656f36754b5668376e6157384c6948305a45457467554f412b34545a6c4977
2801
4a0e 5453362044726f69642074657374
```

Whitespace/newlines above are for readability, not wire bytes. Protobuf field
keys are `0a` (email), `12` (password), `28` (sync version), `4a` (device
name). Protobuf permits field reordering; an interoperable serializer need
not reproduce this exact ordering as long as decoding gives the same fields.

## 6. Successful reply and session lifecycle

The standalone HTTP 200 reply was **1101 bytes** and decoded as:

| Reply field | # / type | Observed result (no secret contents) |
|---|---|---|
| `error` | 5 / enum | **200 = ERROR_LOGIN_OK** |
| `session` | 2 / string | Present, 36 characters |
| `uuid` | 4 / string | Present, 36 characters |
| `key` | 1 / bytes | Present, **61 bytes**; wrapping format unresolved |
| `limits` | 3 / repeated `Limits` | Present |
| `purge` | 6 / int64 | Present, nonzero; don't invent an expiry duration |
| `username` | 8 / string | Present |
| `myts_id_data` | 9 / message | Present |
| `mytsid_user_cert` | 10 / message | Present |
| `push_token` | 12 / string | Present; secret, not needed just to log in |
| `permission` | 13 / message | Present |
| `alternative_login_info` | 16 / message | **Absent** in this request mode |
| `recovery_key_count` | 21 / int32 | Present (new-build field) |

Presence/lengths above describe **one tested request mode**, not invariants
for every account or server release. The protobuf also declares addon status,
avatar and user data; their absence here is not an error.

### Success check

For the demonstrated flow, require all of:

```text
HTTP status == 200
body parses as LoginSession
LoginSession.error == ERROR_LOGIN_OK (200)
LoginSession.session is nonempty
```

**Do not confuse HTTP 200 with protobuf 200.** An empty/default protobuf has
`error=0`; that is **not** the success actually observed. The legacy Kotlin
code's tolerance of `UNKNOWN_ERRORCOMMON=0` is not evidence that the server
returns it for successful login.

### Session RPCs

All are on `/authentication` with the same method framing:

| Method | Request | Reply | Validation status |
|---|---|---|---|
| `session` | `Session{session=1 string}` | `LoginStatus{error=1 enum, uuid=2 string}` | Schema-confirmed; not called standalone in run40 |
| `deleteSession` | Same `Session` | Same `LoginStatus` | Live-confirmed; **204 = ERROR_SESSION_DELETED_OK** |

Deletion request prefix is `0d` + ASCII `deleteSession`. The actual cleanup
frame was 52 bytes; its reply was `08 cc 01` (field 1 varint 204), **3 bytes**.
Only the session created by the standalone test was deleted.

Persist the successful session and account identifier securely; clear local
tokens on user-requested logout, and distinguish offline cleanup from
confirmed server deletion. Do not send a local database/profile record to
the cloud: `Account_Serializing.proto` describes desktop persistence, not a
login request.

### Renewal is not solved by password login

`LoginSession.alternative_login_info` declares:

```text
renewal_token = 1 string
otp_renewal_token = 2 string
device_id = 3 string
```

All were empty/default because the entire message was absent in the successful
no-device-ID response. Do not fabricate those tokens or assume a login always
returns them. Descriptors also declare `requestAuthToken`, `loginWithAuthToken`
and `loginWithRenewalToken`; their names do not prove a particular renewal
handshake. Run39 observed **no `requestAuthToken`** in its captured replay,
and run40 logged in directly using `login`. Other desktop modes may differ.

## 7. Errors, OTP and current-build schema additions

Application errors belong to `ErrorCommon`; these numeric values come from
descriptors. Only **200 and 204** were observed in run40's standalone calls.

| Value | Name | App interpretation |
|---|---|---|
| 0 | `UNKNOWN_ERRORCOMMON` | Unspecified/unknown; not established success |
| 100 | `ERROR_FE_UNKNOWN_METHOD` | RPC method not accepted |
| 101 | `ERROR_FE_UNKNOWN_DATA` | Request data not accepted |
| 102 | `ERROR_SESSION_OK` | Session-status success (not the login success code) |
| 103 | `ERROR_SESSION_EXPIRED` | Session expired |
| 104 | `ERROR_SESSION_SERVER_OFFLINE` | Session service unavailable |
| 200 | `ERROR_LOGIN_OK` | Login success, still require nonempty session |
| 201 | `ERROR_LOGIN_OFFLINE` | Login service unavailable |
| 202 | `ERROR_LOGIN_FAILED` | Credentials rejected |
| 203 | `ERROR_LOGIN_EMAIL_PENDING` | Email confirmation pending |
| 204 | `ERROR_SESSION_DELETED_OK` | Session deletion success |
| 205 | `ERROR_PUSH_TOKEN_CREATION` | Push-token creation error |
| 206 | `ERROR_AUTH_TOKEN_INVALID` | Auth token rejected |
| 207 | `ERRIR_RENEWAL_TOKEN_INVALID` | Renewal token rejected; spelling is literally `ERRIR` |
| 208 | `ERROR_AUTH_REQUIRES_OTP` | Ask for OTP instead of treating it as wrong password |
| 209 | `ERROR_2FA_OTP_INVALID` | OTP rejected |
| 210 | `ERROR_2FA_OTP_SECRET_MISSING` | OTP secret unavailable |
| 211 | `ERROR_2FA_DEVICE_ID_MISSING` | OTP/device prerequisites unavailable |
| 212 | `ERROR_2FA_RECOVERY_KEY_INVALID` | Recovery key rejected; new-build enum |
| 213 | `ERROR_2FA_NO_RECOVERY_KEYS` | No recovery keys; new-build enum |

No OTP was supplied or requested in the tested account login. Implement an
explicit OTP step using field 6 and the declared errors, but mark device-ID,
OTP-renewal and recovery behavior **untested** until exercised. Login UI must
not enroll/disable 2FA or alter account settings merely to make a test pass.

Newer-build additions absent from the committed older common schema:

```text
LoginData.recovery_key = 10                    string
LoginSession.deletion_info = 17                DeletionInfo message
LoginSession.remaining_recovery_keys = 18      int32
LoginSession.recovery_keys_used_count = 19     int32
LoginSession.remaining_recovery_keys_known = 20 bool
LoginSession.recovery_key_count = 21           int32
ErrorCommon recovery errors = 212, 213
```

Unknown protobuf fields should be tolerated. For a new binding generation,
render and verify the current descriptors instead of manually editing a
file marked generated. Do not infer account-deletion or recovery operations
from these extra reply fields.

### Desktop bridge codes are a separate namespace

The CEF bridge exposes `loginAccount(email, password, otp, callback)` and
`getAccountHashedPassword(callback)`. Its callback codes are:

```text
LoginOk=1, LoginOffline=2, LoginFailed=3, EmailPending=4,
SessionOk=5, Login2FARequired=6
```

They are **not** `ErrorCommon` numbers. Captured desktop callbacks returned
`code=1`; only the subsequent standalone protobuf decode established 200.
The bridge getter returned the same Base64 string as the actual wire password.

## 8. Distinct encryption derivation — keep separate from login

The producer derives this alongside the login credential:

```text
salt = E || ASCII("ts3Encryption") || P
encryption_value = PBKDF2-HMAC-SHA512(P, salt, 10000, 32)
```

It returns **32 raw bytes** (not the login's 48 bytes and not Base64), and
native input/output matched that calculation. For the first synthetic vector:

```text
92e837501d0748edbbd279e32f49931626851ca6d97b5658e3c522c533654e45
```

This value is **not sent as `LoginData.password`**. It enters desktop account
state through a different setter. It is a useful anchor for future sync
research, **not** proof that `LoginSession.key` is ready-to-use AES key material
or that bookmark ciphertext can already be decrypted. Cipher, framing,
nonce/IV, tag, account-key unwrap and per-item derivations remain unresolved.

Login can be implemented without guessing any of those formats. Keep login,
renewal and sync/import as separately testable milestones.

## 9. Implementation/security requirements for Flutter

- Follow `flutter-migration-plan.md` phase 6: a Dart port or a shared Rust
  implementation is still a design choice. The protocol itself requires no
  changes to TeamSpeak voice command declarations.
- Port the **demonstrated** KDF, not the legacy Kotlin SHA-512-hex encoder
  or its temporary multi-encoding diagnostic. Do not submit speculative
  plaintext/SHA256/SHA512 alternatives to the account.
- Run PBKDF2 away from time-sensitive UI/audio work; await it before building
  the request. Only the derived Base64 value goes into the protobuf.
- Treat **plaintext password, salt, raw DK and Base64 DK as secrets**. The salt
  contains the plaintext password; it is not a harmless random public salt.
  The Base64 credential is replayable authentication material, not safe log
  data. Session, push, renewal and OTP-renewal tokens are also secrets.
- Redact requests/replies, network diagnostics, exceptions and crash reports.
  Logging method, status, field presence and lengths is sufficient.
- Do not persist the password or KDF outputs just to restore a session. Use
  OS-backed secure token storage (the plan names `flutter_secure_storage`),
  not ordinary `shared_preferences` or bookmark JSON.
- HTTP clients must **not silently retry login POSTs** or follow a redirect
  with credential bodies to another origin. Surface failure for an explicit
  user decision; pace manual retries (existing research/app plan: at least
  four seconds), with special care for rate limits.
- TLS and network failures, HTTP non-200, malformed protobuf, credentials
  rejection and OTP-needed states must remain distinguishable. Never retry
  wrong-password/OTP failures in a loop.
- Unknown server enum/field values should produce safe, informative behavior,
  not a crash or a false success. A parsed default/empty reply is not a session.
- A basic successful login does not authorize auto-importing/replacing the
  user's TeamSpeak identity, writing account settings, enrolling 2FA or syncing
  local bookmarks back to the server.

### Acceptance tests before claiming Flutter login works

1. KDF golden tests in §3, including UTF-8 password, ASCII email case,
   password whitespace and locale independence.
2. Synthetic frame test in §5, plus a decode comparison independent of field
   ordering; verify field 5 is 1, not proto3 default 0.
3. Transport test that sees exact endpoint, content type, prefix, and bare
   reply decoding; no real network required.
4. Error mapping tests for HTTP failure, malformed/empty protobuf, 202, 208,
   209 and unknown enums; no successful outcome without a session.
5. Session storage/load/logout tests; a successful reply **without**
   `alternative_login_info` must work without inventing renewal capability.
6. With explicit owner authorization, at most one paced app-account login
   initially, then delete only its own test session; verify the phone's actual
   crypto provider/UTF-8 behavior before saying device login is proven.

## 10. Native evidence map (for auditing, not app hardcoded offsets)

| Address / ABI | Meaning |
|---|---|
| `0x46d9559`: `rsi` URL string, `rcx` framed body string, `r8` media-type string | Actual HTTP sender request hook |
| `0x2a238a0..0x2a24080` | Account login producer calling both derivations |
| `0x2a23bbe` → `0x2a7fc70` | Login KDF call |
| `0x2a7fc70`: sret `rdi`, password string `rsi`, email string `rdx` | Login derivation entry; returns Base64 string |
| `0x2a7f780` | Byte-wise email lowercase via locale facet |
| `0x2a7fd31` → `0x2a81930` | Iterations `0x2710`; wrapper chooses output `0x30` |
| `0x2a83320`: sret `rdi`, password `rsi`, salt `rdx`, output bytes `ecx`, iterations `r8d` | Shared PBKDF2 string wrapper |
| `0x47594a0` | Raw PBKDF2 helper, digest selection 8; output independently matches SHA512 |
| `0x2a81970` → `0x25421e0` | Derived-byte Base64 encoding |
| `0x2a22f91` in `0x2a220b0` | Copying derived password into LoginData |
| `0x2a23d5c` → `0x2a7fe30` | Distinct 32-byte encryption derivation |
| `0x2a72a70` | Account-state setter for that encryption value |

The early SHA-512 sync wrappers were **not** the login KDF. The actual KDF
became visible by following the producer from a first-login synchronous
stack, rather than digging further down an async sender/TLS stack. The
initial negative replay probes were not proof of any particular algorithm.

Audit captures are in `captures/myts/run40/probe-derivation-fixed/`: plaintext
inputs, exact salts, KDF outputs, Base64 result and actual request. Local
assertions confirmed every input/output comparison, including equality with
run39's wire/getter reference. **Do not commit these files**; all committed
goldens use synthetic credentials.

## 11. Known limits and next unanswered questions

1. The Flutter M1 password-login Dart port exists
   (`flutter/lib/src/myts/`, `flutter/test/myts_*_test.dart`) with offline
   goldens, but a **phone-app login has not been demonstrated**: successful
   **Python standalone login** must not be reported as a phone-app login
   until an authorized live test runs from the app.
2. OTP/device-ID/recovery/renewal modes are declared, not live-validated here.
3. `purge` is an int64 server field; the run40 check established nonzero
   presence, not a full unit/timezone/expiry policy analysis. Validate its
   semantics before building renewal/expiration scheduling around it.
4. Account encryption-value derivation is known, but the server's 61-byte
   account key and encrypted sync payload formats remain to be traced.
5. Internationalized email normalization requires a deliberate compatibility
   test; don't generalize one ASCII account to all Unicode addresses.
6. New-build schema regeneration/verification remains outstanding. Old schemas
   still parse the common login fields, but miss the recovery/deletion additions.

These are follow-up tasks, **not blockers to the demonstrated password-login
algorithm**. No more speculative password-encoding or TLS-interception rounds
are needed to establish it.
