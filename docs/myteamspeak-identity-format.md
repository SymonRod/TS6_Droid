# Desktop identity format and UID compatibility

**Status (2026-10-14): step 2 verified with disposable synthetic identities,
including an independent offline desktop-binary oracle. A later explicitly
authorized read-only cloud check also validated two real identity strings in
memory; see the [live handoff](myteamspeak-rust-import-engine.md#authorized-live-read-only-follow-up-2026-10-14).
The original synthetic investigation below used no real account/network.**

This follows [the read-only Rust engine](myteamspeak-rust-import-engine.md).
It proves format/UID compatibility, not a working cloud-to-Flutter importer.

## Representation

The demonstrated desktop identity string is:

```text
decimal_u64_key_offset + "V" + Base64(obfuscated_private_key)
```

The offset is the hash-cash counter, not the security level or the UID. Preserve
it during import; do not generate another key or blindly improve/recreate the
identity. The public-key-derived UID is unchanged when only the offset changes.

Before obfuscation, the key is ASCII standard Base64 of TomCrypt's ASN.1 DER:

```text
SEQUENCE {
  BIT STRING: one significant bit, set for a private key
  INTEGER: 32 (P-256 field size)
  INTEGER: public X
  INTEGER: public Y
  INTEGER: private scalar
}
```

DER integers are positive, minimally encoded, big-endian integers; they are
**not fixed 32-byte buffers**. A high sign bit requires a leading zero byte.
The private scalar must be restored to a 32-byte P-256 value, with left padding
and rejection of negative, zero, oversized and out-of-range scalars.

The obfuscation is not encryption or secure storage. XOR the first 100 bytes
of the Base64 private DER with the desktop's static ASCII mask (bounded by the
input length); SHA-1 the resulting tail from byte 20 up to its first NUL/end;
XOR that digest into the first 20 bytes; Base64 the result. Deobfuscation reverses
these operations. The independent implementation and synthetic mask are in
`tools/myts/identity_vectors.py`; no private identity fixture is stored.

The native library's persisted JSON is different: its `key` value contains
`offsetVBase64(32-byte private scalar)`. `tslib_core::Identity::from_string`
accepts the demonstrated desktop string, and exporting/reloading its own JSON
preserves the UID, offset and locally computed level. This API is **not an INI
identity-export-file parser**. A public UID is not importable private material.

## UID derivation

```text
UID = Base64(SHA1(ASCII(Base64(public_TomCrypt_DER))))
```

The public DER has the unset private-key bit and the size/X/Y integers only.
Hash the **Base64 text**, not raw DER, SEC1/SPKI, private material, obfuscated
text, counter or cloud item UUID. SHA-1 here is the TeamSpeak compatibility
identifier, not a new integrity/authentication design. The resulting 20-byte
digest is standard Base64 (28 characters, including padding).

## Independent evidence

Three public scalars, unsafe for production, are generated at runtime:

| Synthetic scalar | Offset | UID confirmed by desktop and Rust |
|---|---:|---|
| 1 (P-256 generator) | 0 | `6Gj4WmRDl6pf8IWg27Gh0E2Wq2Q=` |
| Big-endian bytes 1 through 32 | 2792354 | `gM4pUv4ozDqs1Z22u18ifJO/9Po=` |
| 32 bytes of `0x80` | 18446744073709551615 | `tiVSHDb2KeglykG74AxUj03v1ZQ=` |

Python independently constructs DER/obfuscation/UID using PyCryptodome only for
the P-256 public point. The scalar-1 coordinates additionally match SEC2's
generator. Rust checks the UID and hashes of Python's obfuscated encodings;
the desktop comparison checks the actual encoded bytes, imported counter and
UID, rather than trusting a same-implementation round-trip.

`tools/myts/gdb_identity_synthetic.py` pins the already installed x86-64 desktop
ELF (MD5 `7eb9fdb89d3da783d3db55845c5066ca`, a build identifier, not a security
check). It runs under `unshare -Urn`, uses an empty temporary HOME/XDG profile,
and stops **before entering application main**. Loader/global constructors run,
but no GUI, account setup or event loop does. It initializes only the desktop's
built-in multiprecision and SHA-1 descriptors, invokes these helpers, compares
synthetic results, and kills the inferior:

| ELF virtual address | Verified purpose |
|---|---|
| `0x26fe000` | Desktop string encoder, including offset and obfuscation |
| `0x26fd980` | Private-key/offset decoder |
| `0x26a2340` | Identity string → allocated public UID, returning status |
| `0x3c428c0` / `0x4b30900` | Register built-in SHA-1 descriptor |
| `0x4b30b70` → `0x4cb43d0`, 424 bytes | Built-in multiprecision descriptor setup |

These offsets are not an application dependency. The probe fails closed on a
different build or missing network isolation; it accepts no external identity.

## Bug found and corrected

The vendored `EccKeyPrivP256::from_tomcrypt` passed a minimal-width scalar
directly to a fixed-width constructor, rejecting the valid scalar-1 desktop
identity with `NoShortKey`. Both the crypto test and core import/storage test
failed before the fix. The two private-DER variants now use checked left padding
instead of taking the integer's unsigned magnitude blindly. Regression tests
cover 1/2/31-byte scalars, the existing compact TS3AudioBot variant, zero,
negative values, oversized values and the P-256 group order. The compact variant
is regression coverage, **not a claim that it is the desktop's storage format**.

No new dependencies, FRB bindings, Flutter changes or account operations were
needed. Existing work in both repositories was preserved; no commit was made.

## Repeatable verification

From `TS6_Droid`:

```bash
captures/myts/.venv/bin/python -m unittest discover -s tools/myts -p 'test_*.py'
captures/myts/.venv/bin/python tools/myts/identity_vectors.py
unshare -Urn env MYTS_HOST_NETNS="$(readlink /proc/self/ns/net)" \
  MYTS_BINARY="$PWD/../teamspeak/TeamSpeak" \
  gdb -batch -nx -x tools/myts/gdb_identity_synthetic.py ../teamspeak/TeamSpeak
```

From `../ts6-lib`:

```bash
cargo test --offline -p tsproto-types --lib
cargo test --offline -p tslib-core identity::tests --lib
cargo test --offline -p tslib-myts
cargo clippy --offline -p tsproto-types --lib --tests --no-deps
cargo clippy --offline -p tslib-core --lib --tests --no-deps
rustfmt --edition 2021 --check crates/tslib-core/src/identity.rs
```

The host lacks the Opus build prerequisites. Core verification linked the
already installed `/lib/x86_64-linux-gnu/libopus.so.0`, via a temporary
`/tmp/opencode/identity-opus/lib/libopus.so` symlink, with `OPUS_NO_PKG=1`
and `OPUS_LIB_DIR=/tmp/opencode/identity-opus`; no system files were changed.
Initially missing **existing locked** Rust dependencies were fetched from the
package registry, then the tests ran offline. This was not an account request.

Results: **11 crypto tests, 4 core identity tests, 50 myTS tests, 29 Python tests
and all three desktop comparisons passed**. Clippy completed with pre-existing
warnings; the core identity file passes formatting. Whole-crate formatting
reports existing unrelated differences and the vendored nightly-format config;
no unrelated formatting changes were applied.

## Remaining importer gates

- Two real cloud `unique_identity` strings subsequently passed the existing
  bounded strict desktop validator and an independent Python DER/P-256/UID
  comparison; counters were preserved. This does not certify every cloud item;
  missing, empty or unsupported material still needs explicit import validation.
- The permissive general-purpose private-DER decoder is **not a full strict
  cloud identity validator**: it does not validate the embedded size/X/Y against
  the private scalar. The strict entry point described below now validates the
  demonstrated desktop format; it does not validate a whole cloud import batch.
- Bookmark references are resolved: a nonempty `Bookmark_Data.identity` is the
  cloud `item_uuid` of the referenced identity (established 2026-10-15 on the
  disposable test account: 2/2 nonempty references matched, no UID/name match).
  "Use Default" is an explicitly empty string. Empty references still ask the
  user once with no preselection; the effective-default rule under several
  `is_default=true` flags is narrowed (the button moves the flag) but unproven.
- Secure multi-identity persistence, atomic/idempotent merge, default/reference
  policies and an opaque Rust key/context boundary for FRB remain application
  work. Lower-level tsclientlib private-key Debug output is not redacted;
  never log it. No new end-to-end zeroization guarantee is made here.
- Real-account import/local-JSON reload was verified only in memory, with no app
  persistence. Desktop UI export/reimport, real-identity desktop-binary comparison
  and server permission preservation were not exercised. Further real-account/
  network validation requires explicit authorization.

## Strict validation and first-import stop gate

`tslib_core::Identity::from_desktop_string` now provides a separate bounded
validator for the demonstrated format. It rejects input longer than 512 bytes
before decoding, requires a decimal u64 offset, and accepts only the canonical
desktop obfuscated private DER. It uses the new vendored
`EccKeyPrivP256::from_ts_obfuscated_desktop` decoder, whose own input is also
bounded. Canonical re-encoding from the scalar checks the private-key bit, size,
public X/Y, DER shape and minimal encoding against the derived P-256 key.
Inconsistent metadata, compact alternate DER, raw scalars, JSON, whitespace
fallbacks and corrupt inputs are rejected with fixed, secret-free errors.

The legacy permissive import/storage API remains unchanged. The strict entry
point neither generates nor improves identities; three synthetic UID goldens
and their original offsets survive validation and local export/reload. Future
persistence must retain the original cloud string separately, because native
JSON export is a different representation. This change makes no additional
end-to-end memory-zeroization or lower-level private-key Debug guarantee.

Verification: 14 vendored crypto tests, 6 core identity tests, 50 myTS Rust tests
and 29 independent Python tests passed offline. Core/crypto Clippy completed
with existing unrelated warnings; myTS Clippy passed with `-D warnings`; core
identity formatting and Rust diff-whitespace checks passed. Flutter regression
checks are separate from these new native entry points, which are not exposed
through FRB yet.

The existing Flutter suite passed all 46 tests in the dev container with network
disabled and the existing prebuilt host FRB library. This covers login/OTP error
classification, Skip/restart and preservation of legacy local data, not the new
strict validator through FRB or interrupted cloud-import persistence. Flutter
analysis reports one pre-existing informational lint at
`flutter/test/myts_api_test.dart:45` (`library_private_types_in_public_api`).
Tests ran on an isolated source copy under `/tmp/opencode`, using offline
`pub get --enforce-lockfile`, without replacing the checkout's generated files.
The independent desktop probe was also repeated: all three synthetic encoder,
offset and UID comparisons passed in an isolated network namespace, with an
empty temporary profile and application main never entered.

`flutter build apk --debug --no-pub` succeeded in the isolated dev-container
copy, including Rust builds for arm64-v8a and x86_64. Only that copy's Gradle
Rust working-directory path was adapted to `/workspace/ts6-lib`, mounted from
`/home/rod/develop/ts6-lib`; no historical host checkout was used. The APK is
available at `flutter/build/app/outputs/flutter-apk/app-debug-myts-identity-gate.apk`
(an ignored artifact; the existing `app-debug.apk` was not replaced). This is
the existing Flutter flow with native identity-validation groundwork, **not an
import-enabled APK**. No app was installed or removed and no phone data changed.

**Integration stops at the bookmark-reference gate.** Available committed
schemas define `Bookmark_Data.identity` as an optional string, but do not prove
whether it names a cloud UUID, UID, display name or another identifier. Existing
synthetic decoder tests preserve references; they do not establish matching
rules. No speculative resolver or local-identity fallback was added. The new
initial-pull request was also unverified at this offline gate; the subsequent
authorized live check accepted it unchanged, but returned only empty bookmark
references and two true default flags. See the live handoff above. FRB context,
secure multi-identity persistence and automatic onboarding import must not be
claimed complete on either evidence path.

Next evidence needed: a synthetic offline desktop reference-resolution test
that distinguishes UUID, UID and name (including missing and ambiguous refs),
or separately authorized analysis of an account with explicit nonempty references.
The synthetic investigation did not authorize real-account access; the later
user grant covered only login/read-only sync, not cloud edits or phone-data
changes. Empty cloud, inconsistent defaults, missing refs, local conflicts,
account changes and interrupted-import policy remain fail-closed gates before
any importer can commit or mark setup complete.
