# Flutter migration plan

Goal: a Flutter client with the same features as the Kotlin app, reusing the
Rust `tslib` core. **The first round does not have to be perfect**: each phase
ends with something runnable, and gaps are written down instead of blocking.

The Kotlin app stays in the repo and keeps shipping until the Flutter app
reaches parity on the "must have" list below. No big-bang switch.

## Status (2026-10-13)

Phases 0-5 are written and committed on `main`. Library is now
[SymonRod/ts6-lib](https://github.com/SymonRod/ts6-lib) (private), checked out
at `../tslib`, with tsclientlib + TS6 declarations vendored; the old forks are
deleted. Flutter builds `tslib-frb` from `../tslib` (see
`flutter/android/app/build.gradle.kts`).

| Phase | State |
|---|---|
| 0-2 connect, channels, users, chat, bookmarks | verified on a real phone and server |
| 3 audio (Kotlin capture/playback, Opus in Rust) | verified both directions |
| 4 foreground service, screen-off audio, notification Disconnect | verified |
| 5 P2P screen share viewer (`flutter_webrtc`) | verified: the stream plays on the phone against a real sharer (rotation, fit/fill, long sessions not yet exercised) |
| 6 file manager, myTS login | not started |

Next, in this order:
1. Split `flutter/` into its own repo that consumes `ts6-lib` (submodule or
   git path); fix the `rustProjectDir` path in `android/app/build.gradle.kts`.
2. Polish pass: BBCode rendering, chat persistence, avatars/icons, `go_router`,
   clean error text (strip the `AnyhowException` prefix), dispose the Rust
   client on `ConnectionLost`, channel passwords, push-to-talk, mute in the
   notification, strip the `.so` (it ships with debug info), fr/it strings.
3. File manager, then myTS login (prefer moving it into Rust).

Known gaps from the first round: screen share has no stream list (entry is the
green icon next to the user), `requestStreamInfo` is tried once per owner, no
stats overlay, ICE errors are generic. NDK in use is 28.2, not 27.x.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Apps | Two separate apps: Kotlin `com.flammedemon.ts6droid`, Flutter `com.flammedemon.ts6_flutter`. Both can be installed side by side; no in-place upgrade, no data migration | Decided by the owner |
| Location | `flutter/` next to `app/` (created with `flutter create`, Android only) | Same repo, shared `docs/`, easy side-by-side comparison |
| Rust bridge | `flutter_rust_bridge` (FRB) over a **new** `tslib-frb` crate in `../tslib` | The existing JNI surface is polling-based (`nativeProcessEvents`); FRB turns that into a Dart `Stream` and generates the types we now hand-mirror in `dev.tslib.*` |
| Fallback bridge | `dart:ffi` on the existing `tslib-ffi` (cbindgen header already there) | If FRB gets in the way; less ergonomic, no codegen of data types |
| State management | Riverpod | Closest match to ViewModel + StateFlow |
| Navigation | `go_router` | |
| Storage | `shared_preferences` (settings), `flutter_secure_storage` (myTS session), `drift` or JSON files (messages, bookmarks) | Mirrors DataStore / EncryptedSharedPreferences / `MessageStore` |
| Platforms | Android first. iOS/desktop later, not designed in now | Keeps round 1 small |

## Must have / later

Must have (round 1 target): connect to a server, identity handling, channel
tree, users, join channel, channel/server/private chat, receive audio, send
audio (push-to-talk or open mic), bookmarks, settings, background connection.

Later: file manager, avatars/icons polish, screen share viewer (P2P WebRTC),
myTeamSpeak login + sync, BBCode rendering polish, fr/it translations review.

## Kotlin → Flutter map

| Kotlin | Flutter |
|---|---|
| `dev.tslib.*` (JNI carriers) | FRB-generated Dart types |
| `bridge/TsClient` (462 lines) | `TsClient` Dart class: FRB event stream → Riverpod notifiers (channels, users, serverInfo, streams, state) |
| `viewmodel/ConnectionViewModel`, `ServerViewModel` (927 lines, the big one) | Riverpod `Notifier`s; split `ServerViewModel` by concern (chat, channel tree, audio) while porting |
| `ui/screen/*`, `ui/component/*` | Widgets; `ServerScreen` (709) and `MessageBubble` (463) are the largest |
| `data/BookmarkStore`, `SettingsStore`, `MessageStore` | Repositories behind plain Dart interfaces |
| `bridge/AudioBridge` (AudioRecord/AudioTrack) | See "Audio" below |
| `service/TsConnectionService` | Foreground service, see "Background" below |
| `bridge/StreamViewer`, `ScreenShareView` | `flutter_webrtc`, phase 5 |
| `bridge/MyTsApi`, `MyTsSessionStore`, `MyTsViewModel` | Dart port or move to Rust, phase 6 |
| `res/values*/strings.xml` | `.arb` files with `intl` (converted by script, not by hand) |

## Phases

Every phase has an exit check. If it fails, stop and fix before the next one.

### Phase 0 — Spike (go/no-go)
- Create `crates/tslib-frb` in `../tslib` exposing: `Identity` create/load,
  `Client.connect`, `Client.events()` as a stream, `getChannels/getUsers`,
  `sendChannelMessage`, `disconnect`.
- `flutter create flutter --platforms=android`, wire the `.so` build into
  Gradle (cargokit or the existing `cargo-ndk` task).
- `nativeInitAndroidContext` must be called before connecting: find the
  Flutter equivalent (small Kotlin plugin class passing the app `Context`).
- **Exit check:** a throwaway screen connects to a real server and prints the
  channel list and incoming chat. No audio, no styling.

### Phase 1 — Core data layer
- Port `TsClient` and the state notifiers; port `ServerBookmark` /
  `BookmarkStore` / `SettingsStore`.
- Unit tests for event → state reduction (reuse cases from `app/src/test`).
- **Exit check:** state matches the Kotlin app against the same server.

### Phase 2 — Screens
- Connection screen, server screen (channel tree, user list, chat), theme.
- Use hardcoded English first; strings via `.arb` in the same phase only if it
  is cheap.
- **Exit check:** can connect, browse, join a channel and chat from the UI.

### Phase 3 — Audio (highest risk, do not underestimate)
- Today Kotlin owns capture/playback and calls `sendAudio`/Opus through JNI.
  Options, in order of preference:
  1. Move capture/playback into Rust (`oboe`/`cpal`) so Dart never touches
     PCM. Best latency, one implementation for future platforms.
  2. Keep `AudioBridge` as Kotlin code behind a Flutter platform channel,
     feeding bytes to FRB. Fastest to get working; throwaway if we go iOS.
- Start with option 2 if round 1 needs to ship quickly, and record the debt.
- **Exit check:** two-way voice with acceptable latency, mute/PTT working.

### Phase 4 — Background and lifecycle
- Foreground service keeping the connection alive (`flutter_foreground_task`
  or a native service launched from a plugin), notification with disconnect.
- Handle rotation, process death, permission prompts (mic, notifications).

### Phase 5 — Screen share viewer
- `flutter_webrtc` plus the TS6 signaling already exposed by `tslib`
  (`joinStream`, `sendStreamSignaling`, `requestStreamInfo`).
- Port the logic from `StreamViewer.kt` (397 lines) behind the same Dart API.
- Most uncertain item: treat as an experiment, parity not guaranteed.

### Phase 6 — File manager, myTeamSpeak
- File manager: JSON listing parsing from `TsClient.parseFileEntries`.
- myTS login: password derivation and protobuf schemas are in
  `docs/myteamspeak-*.md` and `docs/proto/`; prefer moving it into Rust so
  Dart and Kotlin share one implementation.

### Phase 7 — Parity pass and switch
- Side-by-side checklist, translations, icons, store listing; then decide
  whether `app/` is retired.

## Accepted shortcuts for round 1
- Android only; no tablet/landscape polish.
- English strings only until phase 2 finishes.
- No file manager, avatars may be missing, no screen share, no myTS.
- Audio may use the platform-channel path (phase 3, option 2).
- No migration of user data between the two apps (different IDs); write an
  export/import later if people ask.

## Open questions
- Is iOS a real goal? If yes, choose audio option 1 in phase 3.
- Where does the FRB crate live: in `../tslib` (shared with Python/bot) or in
  this repo as a thin wrapper depending on `tslib-core`?

## Tooling checklist
- [x] Flutter SDK (`~/develop/flutter`; a newer version is available)
- [x] `cargo`
- [ ] `cargo-ndk` (not on PATH in this session)
- [ ] `flutter_rust_bridge_codegen`
- [ ] Android NDK 27.x reachable from the Flutter Gradle build
