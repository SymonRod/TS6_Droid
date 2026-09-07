# AGENTS.md

Working notes for coding agents on **TS6 Droid**, a free and lightweight
TeamSpeak 3/6 client for Android.

## Project layout

```
app/src/main/
├── java/dev/tslib/          # JNI classes (bridge to the Rust library)
├── kotlin/dev/tsdroid/
│   ├── bridge/              # TsClient (coroutines + StateFlow), Audio/Avatar/File/Icon caches
│   ├── data/                # BookmarkStore, ServerBookmark, MessageStore, SettingsStore
│   ├── service/             # TsConnectionService (foreground service)
│   ├── viewmodel/           # ConnectionViewModel, ServerViewModel
│   └── ui/
│       ├── screen/          # AppNavigation, ConnectionScreen, ServerScreen
│       ├── component/       # ChannelTree, ChatView, FileManagerDialog, MessageBubble, UserItem
│       └── theme/
└── res/                     # values (en), values-fr, values-it, xml/locales_config.xml
docs/                        # protocol research and design notes
```

The native library `tslib` (Rust) handles the TeamSpeak protocol over JNI and
**lives outside this repository**, at `../tslib`. It is a Cargo workspace
(`tslib-core`, `tslib-audio`, `tslib-chat`, `tslib-channel`, `tslib-ffi`,
`tslib-jni`, `tslib-python`, `tslib-bot`) built on
[tsclientlib](https://github.com/ReSpeak/tsclientlib).

`tslib` depends on a **fork**,
[SymonRod/tsclientlib](https://github.com/SymonRod/tsclientlib) (branch
`ts6-client-is-streaming`), whose only change is declaring TeamSpeak 6
arguments upstream does not know — currently just `client_is_streaming`. The
declarations live in a submodule, forked as
[SymonRod/tsdeclarations](https://github.com/SymonRod/tsdeclarations) on the
same branch; cargo checks it out on its own, so no `git submodule` step is
needed here. Adding a TS6 argument means a commit in *both* forks: the field in
`declarations/Messages.toml` (plus the command's `attributes`, optional with
`?`) and, for a book property, `declarations/Book.toml` with `opt=true`; then
bump the submodule pointer in the tsclientlib fork.

## Build

```bash
./gradlew buildRustLibs      # cargo-ndk → app/src/main/jniLibs (arm64-v8a, x86_64)
./gradlew assembleDebug      # buildRustLibs runs automatically before JNI merge
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Requirements: JDK 17, Android NDK 27.x (`ANDROID_NDK_HOME` or auto-detected
under `$ANDROID_HOME/ndk`), Rust with `cargo-ndk` (see `app/new.sh`).

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
- **[docs/screenshare-phase2-plan.md](docs/screenshare-phase2-plan.md)** — the
  working plan for the next step, including where to hook `tsproto` and why the
  obvious hook does not work. Read this before touching `../tslib`.

Summary of what static analysis of the desktop client established:

- Screen sharing signaling uses **TS3-style commands on the existing TeamSpeak
  command channel** (`setupstream`, `joinstreamrequest`, `streamsignaling`,
  `notifystreamstarted`, `notifystreamsignaling`, …), so `tsclientlib` already
  carries them — no new transport, no crypto work.
- Command bodies are **JSON** (`nlohmann::json`), handled by
  `com::teamspeak::video::ScreenshareManager`.
- The media plane is **standard WebRTC** (libwebrtc, OpenH264, VP8/VP9,
  simulcast), in either `STREAM_P2P` or `STREAM_SFU` mode, advertised through
  `virtualserver_capability_extensions`.
- In `STREAM_SFU` mode the SFU is **mediasoup** (`libmediasoupclient` over a
  WebSocket) — a public, documented protocol with an Android client, so the
  viewer is an integration job rather than a reverse-engineering one.
- Viewing someone else's screen needs **no `MediaProjection` permission**; that
  is only required to share the phone's own screen.

Status: exploratory, Phase 1 **and Phase 2 (P2P mode, both roles)** done. **Do
not add screen sharing code to the app yet** — Phase 2 closed the biggest unknown, and
the answer overturns the working assumption: screen-share notifications are
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
§9.4/§9.6 cannot be tested. §9.5 (TURN relaying) stays open but needs only a
client behind symmetric NAT.
Note that `tsclientlib` drops genuinely unknown *commands* — arguments and all
— before `tslib` ever sees them, so the capture hooks `tsproto`'s packet event
listener instead of listening in `tslib-core`.

The one piece already **in** the app is `client_is_streaming`, the client
property that says *who* is sharing — it needs no signaling, only the argument
declaration in the tsclientlib fork described above. It reaches the UI as
`User.isStreaming` and shows as a green screen icon in `UserItem`. Everything
else stays out of the app until the protocol is confirmed.
