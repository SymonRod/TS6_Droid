# myTeamSpeak read-only Rust import engine

**Status (2026-10-14): Rust engine verified offline and in one explicitly
authorized, bounded read-only real-account check. Login, account-key unwrap,
initial pull and identity/bookmark decoding succeeded; bookmark-to-identity
resolution remains unverified.**
This is step 1 of the identity/bookmark import delivery. The Flutter integration
(FRB, transport, secure storage, onboarding, identity choice) is described in the
last section and is verified **offline only**; it has not been run on a phone or
against the real service.

Implementation: `../ts6-lib/crates/tslib-myts/` (the checkout on this machine;
the project's historical `../tslib` path is absent).

## Implemented boundary

- Password login retains `LoginSession.key` as unchanged binary `wrapped_key`.
  Authentication can succeed without it; sync unlock cannot.
- `unlock_account_key(email, password, wrapped_key)` runs the demonstrated
  `ts3Encryption` KDF and authenticates exactly the version-2 61-byte GCM
  envelope. Unsupported versions, wrong passwords and altered bytes fail
  closed, without any item-provider fallback.
- `build_initial_pull(session)` prepares a read-only `requestServerItems`
  request to `/synchronization`, V1_1, with explicit BOOKMARK/IDENTITY classes
   and no local versions, details or blobs. Its wire shape is tested offline
   and was accepted by the service without correction in the live check below.
- `parse_pull(status, body, account_key, limits)` decodes sync envelopes,
  checks item integrity before parsing, validates UUID/content/class
  consistency, and returns typed bookmark/identity data plus separate tombstones
  and class/version metadata. Failure returns no partially decoded batch.
- Proto2 absent/empty/zero/false distinctions, default-identity flags, all
  declared bookmark fields, channel passwords and opaque identity references
  are retained. Outer item versions are not equated with inner sync versions;
  `item_type` is not mistaken for the outer class discriminator.
- Duplicate classes/UUIDs, invalid UTF-8/types/ranges and oversized replies,
  blobs, strings, field tables and collections are rejected. Known unsupported
  classes are counted but not decrypted, including CONFIG/chat material.
  Unknown field numbers are reported without claiming to restore their values.

Rust remains **sans-IO**. The future Dart transport performs the actual HTTPS
POST with normal certificate verification, no redirects, receive limits and
timeouts. No HTTP dependency, cloud writer, renewal or credential-persistence
path was added.

## Security and interpretation

`AccountKey` is non-cloneable and redacted in Debug. Its owned bytes, working
plaintext, decoded private identity material/passwords and initial-pull buffers
zeroize on drop. This is not a claim to wipe caller/FFI copies, existing login
session strings, compiler temporaries or ring's internal expanded GCM key.
Secure storage and logout/account-switch lifecycle remain application work.

The item format's exposed SHA-512 digest is **not a MAC/authenticity guarantee**.
Keep the account-key GCM and item CTR formats separate, and retain verified TLS.
See [account unwrap](myteamspeak-key-unwrap-protocol.md) and
[item decryption](myteamspeak-bookmark-decryption-protocol.md).

The engine returns decoded protocol data, **not an import-ready/complete cloud
restoration guarantee**. In particular:

- Decoded batches do not validate private identity material. Synthetic desktop
  format/UID compatibility is now independently verified in
  [step 2](myteamspeak-identity-format.md). A bounded strict desktop-format
   validator is available in `tslib-core` and passed for both sampled cloud
   identities. It remains separate from this decoder and is not an
   import-batch/reference validator.
- A bookmark identity reference remains opaque; its actual matching rules
  still need to be established, not assumed from the synthetic fixtures.
- Missing material/connection fields/default identity/references and empty
  cloud fallback need application validation policies. No identity is generated
  or substituted by this decoder.
- A returned batch does not prove full-snapshot completeness, cursor advancement
  or deletion semantics for future incremental synchronization.
- Duplicate rejection inside one reply is not persistent deduplication/merge
  across imports. The caller must preserve account ownership with cloud IDs.
- The existing FRB login API and generated Dart files are unchanged; the new
  engine is not yet exposed to Flutter. Plan an opaque key/context boundary
  rather than casually copying raw account keys into Dart.

## Verification and next gate

```bash
# Rust checkout
cargo test --offline --manifest-path ../ts6-lib/Cargo.toml -p tslib-myts
cargo clippy --offline --manifest-path ../ts6-lib/Cargo.toml \
  -p tslib-myts --all-targets -- -D warnings
cargo fmt --manifest-path ../ts6-lib/Cargo.toml -p tslib-myts -- --check

# Independent synthetic Python crypto reference (no captures/credentials read)
captures/myts/.venv/bin/python -m unittest discover -s tools/myts -p 'test_*.py'
```

The original offline evidence path covers independent synthetic KDF/GCM/item goldens and
NIST/FIPS primitive vectors; login → unwrap → typed sync decoding; multiple
identity references; field presence/defaults; tombstones; malformed/duplicate/
oversized inputs; and failure after an already valid item. It makes no live
service or real-identity compatibility claim.

Original results: **50 Rust tests and 26 Python tests passed**; crate Clippy
(`--all-targets -- -D warnings`), formatting and repository diff-whitespace
checks passed. Existing work in both repositories was preserved; no commit
was made.

Full `cargo check --offline -p tslib-frb` is blocked on this Linux environment
by missing `pkg-config`/ALSA build prerequisites. The independent crate tests,
Clippy and formatting checks do not require those audio dependencies.

Step 2 is now verified: [desktop identity format and UID](myteamspeak-identity-format.md)
records the independent synthetic desktop oracle, vendored scalar-padding fix
and the new bounded strict desktop-format entry point. The next integration gate
is bookmark-reference semantics: synthetic references are not proof of a
resolver. Multi-identity secure persistence and idempotent Flutter import remain
unimplemented. Flutter Sign in/Skip onboarding already exists; login preserves
a session but does not complete initial setup or import data. The follow-up below
does not integrate app import. Further real-account/network validation requires
explicit authorization.

## Authorized live read-only follow-up (2026-10-14)

### Scope and transport

The owner explicitly authorized reading root `.env` EMAIL/PASSWORD in memory
for login and account synchronization reads only. Both repositories were dirty
before this turn; existing changes were preserved and no commit was made.

The old `standalone_login.py` was audited but **not executed**: it saves
request/reply buffers and invokes `deleteSession`, outside this authorization.
Instead a temporary worker reused `tslib-myts` and the existing strict
`tslib-core::Identity::from_desktop_string` validator. A temporary Python
transport supervised it through private length-bounded pipes. Neither the
worker's secret-bearing pipe nor exception contents were rendered to the
terminal. Only aggregate outcomes/counts, field numbers and HTTP/app statuses
were printed. No real credentials, tokens, keys, identities, bookmark passwords,
UIDs, item IDs, counters, hashes or response bodies were saved as artifacts.

The transport allowed exactly two RPCs, once each:

1. `/authentication:login` — HTTP **200**, successful Rust login classification.
2. `/synchronization:requestServerItems` — HTTP **200**, protobuf status **301**.

It used normal CA/hostname-verified TLS, no redirects/proxies/retries, a
15-second connect timeout, bounded socket reads and a 45-second per-request
deadline (150-second overall watchdog). Receive caps were 1 MiB for login and
8 MiB for sync; declared and streamed sizes were checked. TLS-key logging and
core dumps were disabled. Credentials were not put in shell arguments or
environment variables; passwords/tokens and reply bodies stayed in process
memory/private pipes. No desktop binary/profile/process was used or attached.
Python copies and lower-level Rust private-key allocations do **not** have a
new guaranteed complete-zeroization property; all probe processes terminated.

No cloud write, app-data persistence/replacement, identity generation, server
connection or session deletion was performed. Login necessarily created a
service session; its token was discarded from memory. **Server-side deletion
was not requested or confirmed**, since deletions were excluded by the owner.
Do not silently run cleanup RPCs under a read-only authorization.

### Established results and limits

- The existing initial-pull builder was accepted **unchanged**. No speculative
  request variants or retry loop were needed. This proves acceptance for this
  account/flow, not full-snapshot completeness, cursor or deletion semantics.
- Version-2 account-key GCM unwrap authenticated successfully. The Rust engine
  verified item digests and outer/inner IDs/content classes before returning
  **2 identities and 5 bookmarks**, with **0 supported tombstones**. Unsupported
  classes remained undecrypted; this was not a full account-data restoration.
- Both real identity strings were bounded canonical desktop
  `decimal offset + V + obfuscated Base64 private DER`. Both passed the strict
  validator already present at turn start. Independent Python deobfuscation,
  DER reading, P-256 point derivation and canonical re-encoding agreed with Rust
  on the UID and preserved counter for each identity. No values were printed.
- Export/reload of local JSON was performed **only in memory**; both UIDs and
  counters survived. This is a Rust-only round-trip, not an independent desktop
  comparison. The desktop oracle remains the earlier **synthetic-only** result;
  no desktop comparison or server-permission check used real identities.
- All **5 bookmark `identity` fields were present and empty**, not absent.
  There were **no nonempty references** to compare. Checks against candidate
  item ID, public UID, name or private string thus had **zero observations**,
  not evidence for any matching key. Nonempty reference representation and
  bookmark-to-identity correspondence remain **unresolved**.
- Both identity `is_default` flags were explicitly **true**. The reply does not
  establish a unique effective default, precedence or what an empty reference
  means in the desktop client. Do not choose the first identity, assume an
  empty string means either identity, or regenerate a key to bridge this gap.
- No unknown field numbers appeared in the supported identity/bookmark content.
  Other accounts/key formats, missing material, recovery/renewal, nonempty
  references, alternate defaults and app integration were not exercised.

### Changes and verification

No production request/crypto/import behavior correction was required. Updated
the stale request-builder status comment and crate README. Added one entirely
synthetic Rust regression preserving an explicitly empty bookmark reference
alongside two distinct identities with `is_default=true`; the decoder must not
rewrite the reference or assume the flags are unique. Existing strict-validator
code and all unrelated Flutter/Rust work were preserved.

Verification in this turn:

- **51 `tslib-myts` tests**, crate Clippy (`--all-targets -- -D warnings`) and
  crate formatting check.
- **14 `tsproto-types` tests** and **6 core identity tests**, offline; core
  identity formatting check. Existing vendored compiler warnings remain.
- **29 Python synthetic reference tests**, offline.
- **11 temporary probe tests**, offline: verified TLS/one request, redirect and
  HTTP failure without body reads, declared/streamed size limits, compression
  rejection, deadlines, RPC allowlist, independent synthetic identities,
  inconsistent-point rejection and private-pipe end-to-end/redacted output.
- One live run, exactly **2 POSTs**, producing the aggregate results above.

Temporary probe sources and the runnable worker were removed after use; build
artifacts outside the repositories contain no runtime account data. This is not
an app feature or a persisted real-account fixture. Next gate: establish nonempty-reference and
empty/default selection semantics from independent protocol/desktop evidence
or a separately authorized account already containing explicit references.
Do not create/edit cloud bookmarks to manufacture evidence under this grant.
Resolve that gate and define failure/default policy before secure multi-identity
persistence, an opaque FRB key/context boundary and typed Flutter import.

## Flutter import integration (implemented, offline-verified)

Status: implemented and covered by synthetic tests; **not** exercised against the
real service from the app, and no APK from this work was installed on a device.

### Flow

Sign in -> `unlock_account_key` (password available only during this call) ->
one read-only `requestServerItems` POST -> Rust decrypts, checks integrity and
validates every identity with the strict desktop validator -> typed batch ->
merge into a secure vault -> setup marker.

- **Empty app** (setup incomplete, no identity file, no bookmarks, empty vault):
  automatic import right after login. The app state is re-checked inside the
  commit; if data appeared meanwhile the import falls back to confirmation.
- **App with data** (including a Skip setup): the download waits for an explicit
  confirmation showing counts only. Nothing is stored before it. Cancel drops it.
- **Retry / later import**: the wrapped account key (ciphertext) is stored with
  the session, so an import can be repeated with the stored session and the
  password re-entered. The password and the raw account key are never persisted;
  the key exists only as an opaque Rust handle during the import.

### Rust / FRB (`tslib-frb::myts`)

- `my_ts_unlock_account_key`, `my_ts_build_initial_pull`, `my_ts_parse_pull`,
  opaque `MyTsAccountKey`. `MyTsLoginSuccess.wrapped_key`, `MyTsEndpoint.sync_path`
  and the receive caps (1 MiB login, 8 MiB sync) were added.
- `my_ts_parse_pull` is atomic: a batch or a failure class (`Http`,
  `SessionExpired`, `Server`, `Limit`, `Invalid`, `Integrity`).
- Identities failing `Identity::from_desktop_string` (absent, empty, oversized,
  corrupt, inconsistent metadata) are listed in `invalid_identity_ids`, never
  repaired or regenerated. Bookmarks without an address go to
  `invalid_bookmark_ids`. UID and counter come from the validator.
- Bookmark `identity` keeps absent (`None`) vs empty (`Some("")`) vs opaque.
- `TsIdentity.from_desktop_string` and `key_offset` were added.

### Dart

- Transport (`MyTsApi`, `myTsHttpPost`): verified TLS (no `badCertificateCallback`),
  no redirects or retries, compression disabled and content encodings refused,
  non-200 bodies not read, declared and streamed size caps, 15 s connect timeout,
  45 s overall deadline.
- `AccountVault`: one secure-storage entry holding imported identities
  (original desktop strings), bookmarks (including server and channel passwords)
  and the local identity links. One write per import, read back and rolled back on
  failure. Unreadable content throws; it is never treated as empty.
- Items are keyed by a hash of account (normalized email) and cloud ID, so a
  repeated import is idempotent and cloud IDs and ownership are preserved. Same
  cloud ID with different content is a reported conflict and the stored copy is
  kept. A new identity whose UID already exists (vault or local identity file) is
  not added twice. Invalid items are skipped and counted. An empty cloud stores
  nothing and does not complete setup.
- The session store's `clear()` removes only its own keys. It used to call
  `deleteAll()`, which would have destroyed the vault in the shared secure storage.
- `OnboardingStore.isComplete()` also recognizes vault data. Setup is marked
  complete only after imported data was stored.

### Identity choice before connecting

The bookmark-to-identity reference is **not** used to select anything: its
matching rule is unproven (see the live follow-up above). An imported bookmark
connects with an identity the user picked (nothing is preselected, the first or
default identity is never taken). The choice is stored as a separate local link
in the vault; the cloud reference is never altered. A link to an identity that no
longer exists asks again. Own bookmarks and manual addresses keep using the local
identity file when it exists; otherwise the user chooses (one choice is remembered
as the local default). A new local identity is created only if the user explicitly
selects "Create a new local identity". `ServerController.connect` now requires an
identity and no longer generates one. Background auto-reconnect never prompts: with
no settled identity it does not connect. An imported bookmark without a nickname
uses the nickname stored with the chosen identity, else asks for one.

### Limits and open decisions

- Account ownership is the normalized login email. The login `uuid` is not used:
  it is not known whether it is stable across sessions.
- No effective-default rule, nonempty-reference resolver, incremental sync,
  deletion handling (tombstones are counted and ignored), renewal, contacts or
  cloud writes. Cloud changes to an already imported item are reported as
  conflicts and not applied.
- Imported bookmarks are listed read-only (connect and change identity); they
  cannot be edited or removed in the app yet. Only server/channel password,
  address, port, nickname, default channel and the cloud reference are used.
- The legacy local identity file (`identity.txt`) stays as before (plaintext in
  app storage); only imported identities use secure storage.
- A mid-import crash cannot leave a half-applied vault (single write), but the
  secure-storage backend's own durability was not tested on a device.
- Dart/FRB `String` copies of imported secrets are not zeroizable.

### Verification (no real account, no network)

- Rust: 51 `tslib-myts` tests, 6 new `tslib-frb` conversion tests, 6 core identity
  tests, 14 `tsproto-types` tests; `tslib-myts` Clippy `-D warnings` and formatting.
  `tslib-frb` Clippy was not run (no clippy in the container).
- Flutter: 142 tests passed (the 46 earlier ones plus new suites for planner/vault,
  the end-to-end flow, the identity resolver, the loopback transport and the import and
  connection widgets); `flutter analyze` reports only the pre-existing info lint.
  The flow tests use real Rust with synthetic
  replies generated by `tools/myts/pull_fixture.py` (account key 0..31, public
  synthetic identity scalars, placeholder hosts and passwords).
- Host FRB library for tests: build `tslib-frb` in the dev container with a stub
  `libasound` (soname `libasound.so.2`) and point `TSLIB_FRB_LIB` at it.
- Debug APK built in the dev container (`flutter build apk --debug`):
  `flutter/build/app/outputs/flutter-apk/app-debug.apk` (ignored artifact). Not installed.
