# AGENTS.md

Working notes for coding agents on **TS6 Droid**, a free and lightweight
TeamSpeak 3/6 client for Android.

## Project layout

```
app/src/main/
├── java/dev/tslib/          # JNI classes (bridge to the Rust library)
├── kotlin/dev/tsdroid/
│   ├── bridge/              # TsClient (coroutines + StateFlow), Audio/Avatar/File/Icon caches, StreamViewer (WebRTC)
│   ├── data/                # BookmarkStore, ServerBookmark, MessageStore, SettingsStore
│   ├── service/             # TsConnectionService (foreground service)
│   ├── viewmodel/           # ConnectionViewModel, ServerViewModel
│   └── ui/
│       ├── screen/          # AppNavigation, ConnectionScreen, ServerScreen
│       ├── component/       # ChannelTree, ChatView, FileManagerDialog, MessageBubble, UserItem, ScreenShareView
│       └── theme/
└── res/                     # values (en), values-fr, values-it, xml/locales_config.xml
docs/                        # protocol research and design notes
```

The native library `tslib` (Rust) handles the TeamSpeak protocol over JNI and
**lives outside this repository**, in
[SymonRod/ts6-lib](https://github.com/SymonRod/ts6-lib), checked out at
`../tslib`. It is a Cargo workspace (`tslib-core`, `tslib-audio`, `tslib-chat`,
`tslib-channel`, `tslib-ffi`, `tslib-jni`, `tslib-frb`, `tslib-stream`,
`tslib-python`, `tslib-bot`).

`tsclientlib` (a fork of [ReSpeak/tsclientlib](https://github.com/ReSpeak/tsclientlib))
and its TeamSpeak 6 declarations are **vendored** in that repo under
`vendor/tsclientlib/` (declarations in
`vendor/tsclientlib/utils/tsproto-structs/declarations/`) and built as path
dependencies, so there are no separate forks or submodules to keep in sync.
Adding a TS6 argument is one commit in `ts6-lib`: the field in
`declarations/Messages.toml` (plus the command's `attributes`, optional with
`?`) and, for a book property, `declarations/Book.toml` with `opt=true`.
To pull upstream changes use `git subtree pull --prefix=vendor/tsclientlib`.

The Flutter port lives in `flutter/` (see `docs/flutter-migration-plan.md`) and
uses the `tslib-frb` crate of the same library.

## Product direction

Read **[docs/product-direction.md](docs/product-direction.md)** before planning
onboarding, identities or myTeamSpeak work. The agreed goal is near desktop
feature parity, including contacts and account chat in future deliveries.
First setup offers myTeamSpeak Sign in or Skip; sign-in on an empty app
automatically imports supported identities and bookmarks, preserving their
relationships. Existing local data must not be silently replaced. Multiple
identities are part of the first import design, not a late manual-only feature.
This product decision supersedes conflicting historical milestone/non-goal
wording; it does not imply that import, ongoing sync or account chat already work.

## Build

```bash
./gradlew buildRustLibs      # cargo-ndk → app/src/main/jniLibs (arm64-v8a, x86_64)
./gradlew assembleDebug      # buildRustLibs runs automatically before JNI merge
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Requirements: JDK 17, Android NDK 27.x (`ANDROID_NDK_HOME` or auto-detected
under `$ANDROID_HOME/ndk`), Rust with `cargo-ndk` (see `app/new.sh`).

Optionally, the Flutter app can be built in a Docker container (JDK, Flutter,
Android SDK/NDK, Rust and `adb` preinstalled) instead of a local toolchain, e.g.
`docker/dev.sh apk debug`. See [docker/README.md](docker/README.md), including
how to reach a phone from WSL2. Using it is a convenience, not a requirement.

`buildRustLibs` keeps unstripped copies of the `.so` files in `../tslib/symbols/`
for `ndk-stack`, then strips the ones packaged into the APK.

## Configuration

| Setting | Value |
|---|---|
| `applicationId` | `com.flammedemon.ts6droid` |
| `namespace` | `dev.tsdroid` |
| `minSdk` / `targetSdk` / `compileSdk` | 29 / 35 / 35 |
| JVM target | 17 |
| ABIs | `arm64-v8a`, `x86_64` |
| Audio | Opus, 48 kHz, mono, 20 ms frames |

Dependencies are declared through the version catalog in
`gradle/libs.versions.toml` — add libraries there, not inline in
`app/build.gradle.kts`.

## Conventions

- **UI**: Jetpack Compose with Material 3. State flows from `TsClient`
  (`StateFlow`) through a ViewModel to composables; composables stay stateless
  where practical.
- **JNI boundary**: `dev.tslib.*` are plain Java classes mirroring the Rust FFI.
  Keep them dumb data carriers; put logic on the Kotlin side in `bridge/`.
- **Strings**: every user-facing string belongs in `res/values/strings.xml`
  (English, the default) with translations in `values-fr` and `values-it`.
  Locales are declared in `res/xml/locales_config.xml`.
- **Language**: code, comments, commit messages and documentation are written in
  **English**. (The `README.md` is currently in French — a legacy exception.)
- **Background connection**: `TsConnectionService` is a foreground service with a
  persistent notification; anything that must survive the Activity goes there.

## Ongoing research

### TeamSpeak 6 screen sharing

Start with **[docs/screenshare-handoff.md](docs/screenshare-handoff.md)** if
you're picking this up in a new session — status, what Phase 2 found, and the
recipe for re-running the capture tool. Then, in order:

- **[docs/screenshare-protocol.md](docs/screenshare-protocol.md)** — the schema
  reference (Phase 1 output). Start here for anything concrete.
- **[docs/screenshare-research-plan.md](docs/screenshare-research-plan.md)** —
  rationale and roadmap. The protocol document supersedes it where they differ.
- **[docs/screenshare-phase4-plan.md](docs/screenshare-phase4-plan.md)** — the
  build plan for the next step, the P2P viewer: what to write, in what order,
  and the wire details that bite. Read this before touching `../tslib`.
- **[docs/screenshare-phase2-plan.md](docs/screenshare-phase2-plan.md)** — the
  capture plan, including where to hook `tsproto` and why the obvious hook does
  not work. Historical now, except for re-running a capture.

Summary of what static analysis of the desktop client established:

- Screen sharing signaling uses **TS3-style commands on the existing TeamSpeak
  command channel** (`setupstream`, `joinstreamrequest`, `streamsignaling`,
  `notifystreamstarted`, `notifystreamsignaling`, …), so `tsclientlib` already
  carries them — no new transport, no crypto work.
- Command bodies are flat TS3 `key=value` commands, not JSON-wrapped
  (Phase 2 overturned the early assumption based on
  `com::teamspeak::video::ScreenshareManager` / `nlohmann::json` symbols).
  Only `notifystreamsignaling` carries JSON, in a single `json=` parameter.
- The media plane is **standard WebRTC** (libwebrtc, OpenH264, VP8/VP9,
  simulcast), in either `STREAM_P2P` or `STREAM_SFU` mode, advertised through
  `virtualserver_capability_extensions`.
- In `STREAM_SFU` mode the SFU is **mediasoup** (`libmediasoupclient` over a
  WebSocket) — a public, documented protocol with an Android client, so the
  viewer is an integration job rather than a reverse-engineering one.
- Viewing someone else's screen needs **no `MediaProjection` permission**; that
  is only required to share the phone's own screen.

Status: Phase 1 **and Phase 2 (P2P mode, both roles)** done, **and the
Phase 4 P2P viewer is implemented and verified live** (desktop sharer →
phone on Wi-Fi and on mobile data, AV1 2560x1440 hardware-decoded; join
timeout, mid-session stop and cross-channel shares exercised live — only the
`refused` path still needs a manual `respondjoinstreamrequest decision=0`
from a fake sharer, since the desktop client in private mode ignores the
request instead of refusing it). The viewer lives in `bridge/StreamViewer.kt`
(`org.webrtc`, STUN-only with the two hardcoded TeamSpeak servers, paced
candidates) with `StreamListDialog` / `StreamViewerOverlay` in
`ui/component/ScreenShareView.kt`, fed by `TsClient.streams`,
`streamJoinResponses` and `streamSignaling`. Screen-share notifications are
**not** JSON-wrapped. They are ordinary flat TS3 `key=value` commands, same
shape as any other notify (`notifystreamstarted`, `notifystreaminfo`,
`notifystreamclientjoined`, `notifystreamstopped`, `joinstreamrequest`). Only
`notifystreamsignaling` carries JSON, in a single `json=` parameter shaped
`{"cmd":"iceCandidate","args":{mLine,mid,sdp}}` — and even the SDP **offer**
skips that command, riding instead as a plain `offer=` parameter on
`notifyrespondjoinstreamrequest`. Full evidence:
`screenshare-protocol.md` §0, §9a (viewer side) and §9b (broadcaster side —
every client → server command now has a confirmed wire spelling, and note that
`setupstream` requires `accessibility` where `notifystreamstarted` says
`access`). SFU mode is **blocked upstream**: TeamSpeak has not released the
SFU, so `virtualserver_sfu_endpoint` is inert on self-hosted servers and
§9.4/§9.6 cannot be tested. §9.5 (TURN relaying) is **answered**: the
TeamSpeak ICE servers reflect but do not relay, while the mobile NAT measured
so far is endpoint-independent — hole punching works, confirmed live on mobile
data with no relay.
Note that `tsclientlib` drops genuinely unknown *commands* — arguments and all
— before `tslib` ever sees them, which is why the stream commands are declared
in the fork above; the capture tool hooks `tsproto`'s packet event listener
instead of listening in `tslib-core`.

`client_is_streaming`, the client property that says *who* is sharing, reaches
the UI as `User.isStreaming` and shows as a green screen icon in `UserItem`.

### myTeamSpeak login

The current implementation target is **Flutter**, not the legacy Kotlin app.
Start with **[docs/myteamspeak-login-protocol.md](docs/myteamspeak-login-protocol.md)**
for the demonstrated password derivation, HTTP/protobuf contract, synthetic
goldens and security requirements. Current crypto follow-ups (2026-10-14):
**[docs/myteamspeak-key-unwrap-protocol.md](docs/myteamspeak-key-unwrap-protocol.md)**
and **[docs/myteamspeak-bookmark-decryption-protocol.md](docs/myteamspeak-bookmark-decryption-protocol.md)**.
Run41b is the valid offline capture; run41 failed before login.

Password login now works live from the Flutter app. Its protocol logic (KDF,
`application/ts3cloud` framing, protobuf codec, reply classification) lives in the
Rust crate `tslib-myts` in ts6-lib, exposed through `tslib-frb` (`api` module
`myts`); it is sans-IO, so Dart (`flutter/lib/src/myts/api.dart`) performs the POST.
Anything else myTS-related (sync, unwrap, renewal) should be added to that crate.

Password login succeeded standalone: PBKDF2-HMAC-SHA512, 10,000 iterations,
48 bytes, salt = ASCII-lowercased UTF-8 email + `ts3Login` + UTF-8 password,
then standard Base64; login `sync_version=V1_1`. The legacy Kotlin SHA-512-hex
encoder/diagnostic is incorrect and must not be ported. Version-2 account-key
GCM unwrap and all five captured bookmark decryptions are demonstrated offline.
Items use the raw account key, AES-256-CTR-128LE and an exposed unkeyed SHA-512
plaintext digest, not the account GCM framing or an authenticity guarantee.
The Rust item primitive, version-2 account-key unwrap and bounded read-only sync
decoder are in `tslib-myts`; see **[docs/myteamspeak-rust-import-engine.md](docs/myteamspeak-rust-import-engine.md)**
for the synthetic/offline evidence and scope limits. Synthetic desktop-format
identity encoding/UID compatibility is now independently verified; see
**[docs/myteamspeak-identity-format.md](docs/myteamspeak-identity-format.md)** for
the offline desktop oracle and vendored private-scalar padding fix. One explicitly
authorized read-only live check accepted the unchanged Rust initial pull and
validated two cloud identities (strict format, independent Python UID/counter
comparison) plus five bookmarks in memory. All bookmark references were explicitly
empty and both identities flagged default: nonempty matching and effective-default
selection remain unresolved. See the Rust-engine handoff's live section; no real
desktop comparison, app persistence or cloud write was performed. The Flutter
import path (FRB unlock/pull/validation, bounded transport, secure vault,
automatic empty-app import, confirmed import into existing data, local identity
choice before connecting) is implemented and verified offline with synthetic
data. On 2026-10-15 the owner reported successful live app login, import of
2 identities and 5 bookmarks visible on the home screen, server connection after
identity selection, and reuse of that choice on reconnecting to the same bookmark.
The owner could not find how to change the remembered identity or a management
menu: track this as a UX follow-up, not a verified management flow. No UI change
was requested. Restart persistence, repeat-import deduplication and desktop
UID/permission equivalence were not reported as tested. See the last section of
the Rust-engine handoff. Token renewal, ongoing sync, nonempty reference matching
and effective-default rules remain open.
On this machine the Rust checkout is `../ts6-lib`, not `../tslib`.
Real-account tests require explicit authorization;
credentials, salts, derived values and captures must stay out of logs/docs/git.

### myTeamSpeak contacts, avatars and account chat

Start with **[docs/myteamspeak-contacts-chat-protocol.md](docs/myteamspeak-contacts-chat-protocol.md)**
for the authorized 2026-10-15 demo-account findings and implementation gates.
`/tschat/getContactList` returned one contact while legacy sync CONTACTS and
GROUP_CHATS were empty; CONFIG contained chat credentials. `/user` returned
four avatar state variants and signed download URLs (image bytes/signature
verification not yet tested). Base32 Matrix localparts may include `=` padding.
Earlier standard-UA requests returned Matrix 503 through the gateway and phone
cellular shell (`rmnet_data0`), but the later controlled comparison found
**`User-Agent: Go-http-client/1.1` changes the same login endpoint to HTTP 200**;
do not treat the earlier 503 as a service outage. An authorized Matrix password
login and bounded initial sync then succeeded, with zero joined rooms/events.
**Cleanup warning: the earlier temporary Matrix device/token may remain active
because logout returned 404 and its memory-only identifiers were lost.** The
owner subsequently made revocation optional and authorized a bounded follow-up;
read **[docs/myteamspeak-chat-history-protocol.md](docs/myteamspeak-chat-history-protocol.md)**
§12–17 for the current state (§10–11 are the earlier stop; §17 is the latest
owner-requested stop and next-chat handoff). Exactly one additional
research device was created, with token/ID retained in ignored owner-only local
storage, and reused. Do not create another login or delete guessed devices.
The empty sync is now explained: changing only its encrypted-only timeline
filter reveals one joined direct room and three ordinary plaintext message
events. Broader sync and bounded scrollback agreed. The owner then enabled
`Encrypt Chat` and sent a dummy message: **§14 demonstrates a real encrypted
event → exact-pair cloud pull → type-1 key unwrap/import → successful Megolm
decryption**, first-known/message index 0. The real own-outbound backup had
explicit empty `sender`/`c25519`/`ed25519` strings: a narrowly scoped research
exception handles that without claiming matched metadata or verified device
identity. Default validation remains strict; do not generalize this to incoming
senders/types 2/3. Earlier plaintext is not retroactively encrypted. No key
upload, research message send or cloud write was performed **through §14**.
**§15 records the owner's later authorization for autonomous tests between two
disposable accounts**: one new identifiable research Matrix device only for
account 2; account 1 reused its existing token/device. Public sender device keys
were uploaded and an Olm-encrypted room key shared to existing devices. Exactly
three encrypted dummy events were initially sent account 2 → account 1 in one new
private test room, indices 0/1/2. **§16 corrects the research sender's missing
numeric `chain_index` in `m.room_key`**, required by native TeamSpeak parsing.
The compatible share reused the same Olm/Megolm sessions at actual index 3;
messages **3/4/5 were then read on the official desktop (owner-confirmed) and
independently recovered through a real recipient cloud type-2 backup**, with
exact plaintext and populated sender/Curve25519/claimed-signing-key matches.
No own-type-1 exception was used. Backup JSON `chain_index=0` but actual first
known index is **3**: original 0/1/2 remain unrecovered. No device/session reset,
rotation or research cloud upload occurred. Retain/reuse both protected records;
the sender's crypto is stored as account-key-encrypted libolm pickles, but bearer
tokens are only permission-protected. Do not rerun `--exchange` or create another
device; see §16 for `--recover`, which now reads only the corrected segment 3–5.
The sender phase is `cloud_recovery_completed_for_repair_only`. Only explicit
`--prepare` may create a missing second-account research device; other modes
fail closed. Native compatibility and partial-history tests were added.
The last executed offline suites passed **70 helper + 15 runner tests (85)**;
three later lifecycle tests and the latest CLI mode fence have not yet been
rerun. The owner requested stopping all tests; after that only handoff docs were
updated. No live/background operation remains. Do not start another live test
merely from this handoff; see §17 for safe resumption and outstanding checks.
No production/app Matrix check or corrected-UA phone test was performed;
complete-history recovery, cross-signed incoming-key trust, type-3 forwarding,
rotation, production Rust/Flutter chat and live cleanup remain unverified.
Desktop Away/DND are extended JSON inside Matrix `status_msg`, with base
`online`; its presence enum differs from the avatar enum. Do not fake online
state from avatar availability. The owner requested contacts/avatar Flutter
implementation and a phone/5G check; implementation/device verification must
be recorded separately from these protocol findings. Preserve existing app
data; do not uninstall/clear data to make a phone test work.

### Flutter account-history reader (subsequent 2026-10-15 delivery)

See **[docs/myteamspeak-history-reader.md](docs/myteamspeak-history-reader.md)**.
The owner subsequently authorized pragmatic implementation and disposable-account
tests. A receive-only Flutter history screen and Rust `tslib-myts::history` engine
now implement manual room/history reads, targeted cloud-key recovery, encrypted
account-scoped state and replay bookkeeping. No `/sync`, key publication, sends or
to-device Olm receiver is enabled. Type 3 is unsupported; own type-1 empty metadata
requires a default-off explicit checkbox, never an incoming-key exception.
The app's first explicit connection creates its own labelled Matrix reader device;
later connections reuse the saved token. Unknown login outcomes fail closed.
Focused checks passed 63 myTS + 6 FRB Rust tests and 27 Flutter tests. A newly
authorized real read reused both research Matrix records, obtained one real type-2
backup and verified exact messages 3/4/5 through the new Rust engine and an encrypted
snapshot round-trip in memory. No new Matrix login, send, key write or research-record
change occurred; temporary myTS sessions were cleaned with 204. This is not phone/
Flutter live acceptance or recovery of 0/1/2. Historical Python lifecycle checks
remain unexecuted. Preserve all protected research records and existing app data.
The reader's debug APK is built (arm64-v8a/x86_64) and installed on the owner's
SM-S938B. After a signature-conflict rejection the owner uninstalled the previous
Flutter app themselves; the agent did not uninstall/clear data. The unchanged APK
then installed successfully. Its hash/details are in the reader handoff. No app
launch/login was performed; functional phone acceptance remains pending.
