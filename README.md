# TS6 Droid

Free and lightweight TeamSpeak 3/6 client for Android, built with [tslib](https://github.com/flamme-demon/tslib_multi) (Rust library) and Jetpack Compose.

## Features

- **Connection** to TeamSpeak 3 and 6 servers
- **Bookmarks** with server name and icon (fetched automatically)
- **Automatic reconnection** to the last server
- **Chat** channel and private messages with persistent history
- **Push-to-Talk** with Opus codec (48 kHz, mono)
- **Channel tree** with user list
- **File manager** — browsing, upload, download, folder creation
- **Channel browsing** before connecting (channel picker)
- **BBCode** in messages

## Architecture

```
app/src/main/
├── java/dev/tslib/          # JNI classes (bridge to the Rust lib)
├── kotlin/dev/tsdroid/
│   ├── bridge/              # TsClient (coroutines + StateFlow)
│   ├── data/                # BookmarkStore, ServerBookmark, MessageStore
│   ├── service/             # TsConnectionService (foreground service)
│   ├── viewmodel/           # ConnectionViewModel, ServerViewModel
│   └── ui/
│       ├── screen/          # ConnectionScreen, ServerScreen
│       └── component/       # ChannelTree, ChatView, MessageBubble, ...
└── res/                     # Android resources
```

The native `tslib` library (Rust) handles the TeamSpeak protocol via JNI. The Android `TsConnectionService` keeps the connection alive in the background with a persistent notification.

## Requirements

- **Android Studio** (or Gradle 8.14+)
- **JDK 17**
- **Rust** with [cargo-ndk](https://github.com/nickelc/cargo-ndk)
- **Android NDK** 27.x (via SDK Manager)
- **tslib** cloned next to the project (`../tslib`)

## Build

### 1. Build the native library

```bash
cd ../tslib

ANDROID_NDK=~/Android/Sdk/ndk/27.2.12479018 \
CMAKE_POLICY_VERSION_MINIMUM=3.5 \
cargo ndk -t arm64-v8a \
  -o ../TS6_Droid/app/src/main/jniLibs \
  build --release -p tslib-jni --features vendored-openssl
```

Or via the built-in Gradle task:

```bash
./gradlew buildRustLibs
```

### 2. Build the APK

```bash
./gradlew assembleDebug
```

The APK is located at `app/build/outputs/apk/debug/`.

### 3. Install on a device

```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

## Configuration

| Setting | Value |
|-----------|--------|
| `minSdk` | 29 (Android 10) |
| `targetSdk` | 35 |
| `compileSdk` | 35 |
| Audio | Opus, 48 kHz, mono, 20 ms frames |

## License

This project is free software. See the [LICENSE](LICENSE) file for more details.
