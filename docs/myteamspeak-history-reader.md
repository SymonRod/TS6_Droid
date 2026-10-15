# Flutter receive-only account history

**2026-10-15, subsequent to the research stop in chat-history §17.** The owner
requested a pragmatic usable implementation with focused tests, and separately
authorized use of the disposable accounts again. That authorization was used for
the bounded read check below, not for more sends, new Matrix devices or key writes.

## First delivery

Open **myTeamSpeak → Account chat history**, enter the account password to unlock,
then explicitly choose **Connect / refresh conversations**. The first app connection
creates one labelled `TS6 Droid history reader` Matrix device. Subsequent connections
reuse its stored token/device. Merely opening/unlocking the screen does not log in
to Matrix. Research devices are not copied into the app.

The screen lists joined conversations and reads up to 40 timeline events per page,
with manual refresh and older-message pagination. Text bodies are displayed without
HTML rendering. Names come from room state when available; opaque room IDs are the
fallback. Existing server/channel chat and the contacts/avatar/import work remain
separate and preserved.

Missing receive keys trigger bounded `getGroupSessionData` requests for actual
room/session pairs from the loaded ciphertext. No empty-selector enumeration,
backup upload, key request, key claim/publication, room mutation, message send,
presence change or background sync is implemented. There is deliberately **no
`/sync` cursor** to advance in this delivery: manual joined-room/history reads avoid
coupling an incomplete crypto receiver to Matrix's to-device queue.

## Architecture and safety

- `../ts6-lib/crates/tslib-myts/src/history.rs`: sans-IO requests, bounded protobuf/
  JSON validation, cloud unwrap and `vodozemac` 0.9.0 Megolm receive sessions.
- `tslib-frb/src/myts.rs`: opaque reader/account-key handles and transient transport
  envelopes. Only encrypted snapshots and display data are returned for persistence/UI.
- `flutter/lib/src/myts/history.dart`: TLS-only, no redirects, checked public DNS
  destinations, Go-compatible User-Agent, finite per-request deadline/byte limits,
  secure storage and account/session guards.
- `flutter/lib/src/ui/myts_history_screen.dart`: explicit unlock/connect, room list,
  text history, partial-coverage/errors and unverified-identity indicators; EN/FR/IT.

Local state is one versioned authenticated-encrypted snapshot: AES-256-GCM, random
96-bit nonce, domain/account-separated HMAC-SHA256-derived key from the unlocked
account key. It contains the Matrix device/token, original receive-key material,
events, pagination and replay ledger together. The blob also lives in platform
secure storage, scoped to the myTS account UUID. Neither raw account keys nor chat
passwords are persisted. The password is needed again to unlock after leaving the
screen. Secret transport envelopes are transient and never logged.

The reader stores a login intent before POST. If the response/token persistence is
uncertain, it fails closed rather than logging in repeatedly or replacing the device.
Expired tokens likewise do not silently create another device. Recovery/revocation
UX for those cases remains future work. Signing out closes access through the
current app session but does not claim to revoke the separate Matrix token; the
account-scoped encrypted history remains retained, not silently erased.

The actual receive-session first-known index is authoritative. JSON `chain_index=0`
does not imply complete history. Sender/Curve25519 associations are checked against
events; claimed Ed25519 material is retained and syntax-checked, **not cross-signed
or independently device-verified by the app**. Decrypted inner room/type/content and
session IDs are validated. Replay bookkeeping binds room/session/sender/index to
the event ID and ciphertext digest; repeated reads of the same event are allowed,
conflicting reuse does not display plaintext. Bookkeeping is saved before display.

Incoming metadata remains strict. Empty sender/device strings are rejected by
default. An explicit, default-off unlock checkbox permits only the documented
**own-sender type-1, all-three-explicit-empty** case. It cannot authorize incoming
type 2/3 or missing/null/partially empty fields. Its UI explicitly reports absent
sender metadata and unverified identity, including for cached keys.

## Deliberate limits

- Receive-only cloud restoration, **not a full Matrix crypto/device integration**:
  no local Olm account, to-device receive processing, sending ratchet or automatic
  key publication. New keys become readable only if available through the cloud.
- Type 3/forwarding remains unsupported pending trust reconciliation. No claim of
  cross-signing, rotation verification, full history or retrieval of indices 0–2.
- Unlock currently needs a valid stored myTS session and a fresh CONFIG read; cold
  offline unlock is not implemented. Once open, cached data survives failed reads.
- Limits: 128 cached rooms, room-name lookup for the first 30 per refresh, 1,000
  cached events per room, 512 receive sessions, 16,384 replay entries, 12 targeted
  cloud-key attempts per history action; 2 MiB per Matrix/cloud reply and 8 MiB
  encrypted snapshot. Hitting a cap fails rather than silently dropping replay state.
- No attachments, edits/redactions reconciliation, read receipts, typing, presence,
  notifications, automatic account renewal, or Matrix logout/device-management UI.
- Android vault durability, real app Matrix login and phone/5G UI acceptance need
  on-device verification. A host check is not evidence of those capabilities.

## Focused evidence

Five new Rust tests cover independent libolm interoperability/nonzero coverage,
encrypted restart/account isolation/tampering, strict metadata and bounds, replay,
explicit own-type-1 policy and durable no-repeat login intent. The deterministic
public fixture is generated by `tools/myts/generate_history_fixture.py` using the
pinned research libolm and independent Python envelope implementation; it contains
no real-account material.

Executed:

- `cargo test -p tslib-myts -p tslib-frb`: **63 + 6 passed**.
- Flutter history/contact/import-widget selection: **27 passed**, including an
  opaque FRB decrypt/save/reopen path and a locked-screen no-network widget test.
- `flutter analyze --no-fatal-infos`: no errors/warnings; only the pre-existing
  info lint at `test/myts_api_test.dart:51`.
- `cargo clippy -p tslib-myts --all-targets --offline -- -D warnings`: passed.
- `git diff --check`: passed in both repositories.
- Debug APK built successfully for arm64-v8a and x86_64:
  `flutter/build/app/outputs/flutter-apk/app-debug.apk`, SHA-256
  `f31b7a9aeba4c993ed2f76139a0bf74c5a4b49b7586f90ba3244a2bbb3d069ad`.
  Both packaged `libtslib_frb.so` files match the current JNI build byte-for-byte.
  The initial build command hit its execution deadline after native compilation;
  a subsequent build completed successfully. No APK was installed or phone data
  changed. Existing plugin KGP migration warnings remain unrelated follow-ups.

Host verification uses the dev container (ALSA development package installed only
there). The new Flutter fixture test additionally takes
`TSLIB_HISTORY_FIXTURE=/workspace/tslib/crates/tslib-myts/tests/fixtures/history-libolm.json`
and `TSLIB_FRB_LIB=/workspace/tslib/target/debug/libtslib_frb.so`.

### Newly authorized real-account read

The ignored `captures/myts/rust_history_read_check.py` reused both protected Matrix
records after fresh account/CONFIG linkage and `whoami`. Recipient joined-room and
one bounded `/messages` read succeeded, followed by one exact-pair cloud pull.
The controlled sender's public signing key matched the returned type-2 metadata.
Real inputs travelled to the sans-IO Rust example `history_read_check` through stdin
only, never a file, command argument, fixture or tool output.

**The new Rust engine decrypted exactly messages 3/4/5**, matched the known bodies,
reported actual first-known index 3, and repeated the check after an encrypted
snapshot round-trip in memory. No new Matrix login/device, sync/presence request,
send, key query/claim/publication, cloud upload or research-record write occurred.
Both temporary myTS sessions were deleted with application code **204**. This is
real Rust protocol/crypto evidence, not Flutter HTTP/phone/secure-vault acceptance.

The historical 85 Python helper/runner result and later unexecuted lifecycle tests
in §17 are unchanged: those suites were not rerun just to inflate this delivery's
test count. Existing protected records and original unrecovered indices remain intact.

## Phone installation follow-up

The owner connected the Samsung SM-S938B and requested APK installation. The
update was initially rejected with `INSTALL_FAILED_UPDATE_INCOMPATIBLE` because
the existing Flutter app had a different signing certificate. The agent did not
uninstall or clear application data. The owner then reported uninstalling the app
themselves; installation of the unchanged APK above succeeded using
`adb install --no-streaming -r`. Package metadata confirmed the new installation.
No app launch, myTS/Matrix login or phone history/vault acceptance was performed.

### Connectivity-check follow-up

The owner reported `HTTP 400; chat unavailable` specifically from **Check chat
connectivity**, not the history reader. This string belongs to the unauthenticated
`/_matrix/client/versions` probe. Its Dart HTTP path did not use the Go-compatible
User-Agent already used by the Rust history request envelopes. The probe now sends
`Go-http-client/1.1`; unrelated avatar downloads keep their default User-Agent.
EN/FR/IT error text no longer claims that failure of this public check proves chat
login is unavailable, and directs the owner to account history instead.

Seven offline transport tests passed for the default probe path, including the
User-Agent, GET destination, disabled redirects, status preservation (301/400/503),
malformed replies, reply bounds and unchanged avatar User-Agent. The six existing
contact tests and two history tests also passed. Flutter analysis had no errors or
warnings (only the previously documented info lint). A bounded unauthenticated
host comparison against the previously documented public chat host returned
**200 with versions JSON for Go UA, 503 for Dart UA**. This does not reproduce or
prove resolution of the owner's phone HTTP 400, and is not account/chat-login
acceptance. No credentials or research records were used.

For the owner-requested update, the installed APK's signing certificate was
compared with the keystore recovered from the retained previous build container;
SHA-256 fingerprints match. The Docker configuration now persists Android home
(including the debug keystore) instead of losing signing identity with each
ephemeral build container. Never uninstall/clear data to resolve an update error.
On this machine the matching key was seeded into Docker volume
`docker_android-home`, mounted at `/home/dev/.android` by `docker/dev.sh`.
Its certificate SHA-256 is
`36594e7f23787797d56b5a51cb3c5429bfe4c5185b4da28c03e73e62892ad76d`
(public certificate fingerprint, not private key material).

The rebuilt debug APK was signature-verified against that installed certificate
and updated successfully on the owner's SM-S938B with
`adb install --no-streaming -r`. No uninstall or data clear was performed.
Package metadata retained `firstInstallTime=2026-10-15 12:17:37` and advanced
`lastUpdateTime` to `2026-10-15 12:29:19`. Updated artifact:
`flutter/build/app/outputs/flutter-apk/app-debug.apk`, SHA-256
`987adcb1255b3e1c1520c5579e2514e1773215e60627135b4e2acd68c8f5e3d1`.
The agent did not launch the app or perform an authenticated chat operation;
the owner still needs to retry the public check/history UI on the phone.

### HTTPS root cause and security correction (same-day follow-up)

The owner retried the updated app and still saw public-probe HTTP 400 plus the
generic history error after unlock/refresh, without the own-backup opt-in. That
error string is shared by all history failures: it is **not evidence of an
incorrect password or, by itself, proof of a persisted uncertain-login state**.
The own-backup policy does not control Matrix connectivity.

**The User-Agent-only correction above was insufficient.** Both custom
`HttpClient.connectionFactory` callbacks returned a plain `Socket.startConnect`
socket for HTTPS URLs. Dart's custom factory is responsible for TLS itself;
HttpClient does not automatically upgrade that socket. A credential-free Dart
comparison using the old callback reproduced **HTTP 400**, with the response
identifying a plain HTTP request sent to an HTTPS port. The corrected production
factory returned **HTTP 200 and versions JSON** against the same public endpoint.
The comparison used no account login, research record or credentials.

Security scope: this defect potentially sent Matrix login credentials/bearer
tokens and signed avatar-download URLs without transport encryption to port 443.
It does not prove interception or successful Matrix login. The primary myTS
password-login, CONFIG pull and cloud-key POST transport is separate and was not
using either faulty factory. Do not use the affected APKs for account chat. No
account/session/device revocation or credential rotation was performed; those
actions need owner-controlled follow-up, not guessed device deletion or a global
logout. No sensitive payload was captured or logged during diagnosis.

Both paths now share `flutter/lib/src/myts/public_https.dart`: validate HTTPS and
port, reject proxies/local destinations, resolve DNS once, reject empty/mixed
private answers, then return the SDK's native `SecureSocket.startConnect` task.
The original `InternetAddress` from lookup retains the queried hostname for
SNI/certificate-name checking while pinning its checked numeric TCP destination.
No insecure certificate callback, plaintext fallback or new DNS lookup is added.
Production uses default platform trust; the explicit custom context in the
low-level helper is used only by synthetic loopback tests.

Final focused checks passed **33 tests**: seven real-socket TLS/policy tests,
nine probe/history/avatar wiring tests, nine existing POST transport tests and
eight existing contacts/history tests. These establish TLS-first wire bytes,
an encrypted synthetic POST, default rejection of a self-signed certificate,
hostname mismatch rejection, caller timeout during a stalled handshake, existing
DNS/URL guards, shared factory wiring and unchanged credential-body wiping.
The timeout check bounds the awaiting HTTP call; it does not establish immediate
SDK-level cancellation of an in-progress TLS handshake. Flutter analysis found
no errors/warnings, only the pre-existing info lint; `git diff --check` passed.
The preceding fake-client tests alone did not exercise TLS and could not detect
this bug.

The owner explicitly selected **HTTPS correction only**, declining a manual
same-device login-recovery feature. The existing uncertain-login guard, encrypted
history and devices remain untouched. No new login/refresh was executed against
the owner's account, and no automatic retry/reset or recovery button was added.
If a previous attempt saved an uncertain intent, transport correction alone does
not unblock it. Phone acceptance and any later recovery require separate checks.
