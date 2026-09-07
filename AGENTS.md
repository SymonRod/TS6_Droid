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

Two documents, read in this order:

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

Status: exploratory, Phase 1 done. **Do not add screen sharing code to the app
yet** — the next step is Phase 2, capturing a real session with
`../tslib/examples/stream-capture`, planned in `screenshare-phase2-plan.md` with
the open questions in `screenshare-protocol.md` §9 as its checklist. The tool is
written and builds; running it needs a TS6 server with a live sharer. The
largest unknown is how a JSON body attaches to a TS3 command; nothing can be
parsed until that is answered. Note that `tsclientlib` drops these commands *and
their arguments* before `tslib` ever sees them, so the capture hooks `tsproto`'s
packet event listener instead of listening in `tslib-core`.

The cheapest useful increment meanwhile is the `client_is_streaming` client
property: it lets the UI show *who* is sharing before any stream can be decoded.
