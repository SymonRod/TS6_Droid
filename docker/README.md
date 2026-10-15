# Dev container

A self-contained build environment for the Flutter app (`flutter/`), so the host
only needs Docker.

| Component | Version |
|---|---|
| Base | Ubuntu 24.04 |
| JDK | OpenJDK 17 |
| Flutter | pinned commit `6a19cca564` (stable, Dart 3.13; the project needs Dart >= 3.12) |
| Android SDK | platform 36, build-tools 36.0.0, platform-tools (`adb`), CMake 3.22.1 |
| Android NDK | 28.2.13676358 |
| Rust | stable via rustup, targets `aarch64-linux-android`, `x86_64-linux-android` |
| Rust tools | `cargo-ndk`, `flutter_rust_bridge_codegen` 2.13.0 |

Versions are build args at the top of the `Dockerfile`; they mirror the host
toolchain the project was developed with. The image is about 7 GB.

## Quick start

```bash
docker/dev.sh build        # once; slow (SDK download, cargo install)
docker/dev.sh apk debug    # -> flutter/build/app/outputs/flutter-apk/app-debug.apk
docker/dev.sh apk          # release APK
docker/dev.sh install      # adb install -r of the last APK
docker/dev.sh shell        # interactive shell in flutter/
docker/dev.sh flutter analyze
docker/dev.sh cargo --version   # any command runs inside the container
```

`dev.sh` with no argument opens a shell. It exports your UID/GID so files
created in the repo stay owned by you.

## Layout inside the container

| Host | Container |
|---|---|
| this repository | `/workspace/TS6_Droid` |
| `../ts6-lib` (override with `TSLIB_DIR`) | `/workspace/tslib` |

The Rust library [SymonRod/ts6-lib](https://github.com/SymonRod/ts6-lib) lives
outside this repo. `flutter/android/app/build.gradle.kts` expects it at
`../../../tslib` relative to `flutter/android`, which is why it is mounted at
`/workspace/tslib`. The Gradle task `buildRustLibs` runs `cargo ndk` for
`tslib-frb` and copies the `.so` files into `jniLibs`; Rust output goes to
`target/` inside your `ts6-lib` checkout.

If your checkout is elsewhere: `TSLIB_DIR=/path/to/ts6-lib docker/dev.sh apk debug`.

## Caches

Named Docker volumes keep downloads between runs: `gradle-cache`, `pub-cache`,
`cargo-registry`, `cargo-git`. The first build downloads Gradle and all
dependencies (a few minutes); later ones are much faster.

The `android-home` volume also preserves the **debug signing keystore**, so
ephemeral build containers can produce compatible updates. If an app is already
installed, seed this volume with its matching existing keystore before building
an update. Back up that keystore privately; never commit it. **Do not use
`docker compose down -v` to reset caches**: it also deletes the signing key.

Gradle's JVM options are set in the image (`~/.gradle/gradle.properties`,
`-Xmx6g`); the Flutter build runs out of heap with the default. If you reset the
volumes, rebuild the image so the file comes back.

## Connecting a phone (WSL2)

The container uses host networking, so its `adb` client talks to an adb server
on `127.0.0.1:5037` in WSL. Containers started by `dev.sh` are removed on exit
(`--rm`), so a server started inside one dies with it. **Run the adb server in
WSL instead** (any `adb`, e.g. the Android SDK's `platform-tools`):

```bash
adb start-server
```

### Option A: wireless debugging (Android 11+)

Phone and PC on the same network.

1. Phone: Developer options > Wireless debugging > on.
2. "Pair device with pairing code" shows `ip:port` and a code:
   `adb pair <ip>:<pairing-port>`.
3. The main Wireless debugging screen shows a different port:
   `adb connect <ip>:<port>`. This port changes each time the feature is toggled.
4. `adb devices` should list the phone as `device`.

If it cannot connect, a Windows firewall or Wi-Fi client isolation is the usual
cause; try `networkingMode=mirrored` in Windows' `.wslconfig`, or use USB.

### Option B: USB through usbipd-win

WSL2 does not see Windows USB ports by itself.

1. Windows: install [usbipd-win](https://github.com/dorssel/usbipd-win)
   (`winget install usbipd`).
2. PowerShell (admin for `bind`):
   ```powershell
   usbipd list
   usbipd bind --busid <BUSID>            # once; state becomes "Shared"
   usbipd attach --wsl --busid <BUSID>    # every time the cable is plugged in
   ```
   "Shared" is not enough; the device is usable in WSL only when it is
   **Attached**, and Windows no longer sees it while it is.
3. Phone: enable USB debugging (File transfer mode alone is not enough) and
   accept the authorization prompt.
4. WSL: `lsusb`, then `adb kill-server && adb start-server && adb devices`.
   `no permissions` needs a udev rule for the vendor or a `sudo` adb server;
   `unauthorized` means the prompt on the phone was not accepted.

## Installing

`docker/dev.sh install` runs `adb install -r` on
`flutter/build/app/outputs/flutter-apk/app-*.apk`. Known stumbling blocks:

- **Popup on the phone.** Some devices (Samsung, Play Protect) ask to confirm
  USB installs. The install hangs until you tap accept; with a ~235 MB debug
  APK over USB/IP it can also just take a few minutes.
- **`INSTALL_FAILED_VERSION_DOWNGRADE`.** The installed build has a higher
  `versionCode` (the app id is `com.flammedemon.ts6_flutter`). Build with a
  compatible version code. Do not uninstall or clear app data to work around it.
- **`INSTALL_FAILED_UPDATE_INCOMPATIBLE`.** The container's debug keystore
  differs from the one the installed build was signed with. Recover the matching
  original keystore, preserve it in `android-home`, and rebuild/re-sign the APK.
  Compare certificate SHA-256 fingerprints before `adb install -r`. If the key
  cannot be recovered, stop and ask the owner; uninstalling deletes server
  bookmarks, the myTeamSpeak session and saved chats.
- `adb shell pm list packages` can fail with `Shell does not have permission to
  access user 150` (secondary profile); add `--user 0`.

## Things that behave differently from a host build

- `flutter pub get` inside the container may resolve a few dependencies to
  different versions than your host and rewrite tracked files
  (`flutter/pubspec.lock`, `flutter/analysis_options.yaml`,
  `flutter/lib/l10n/app_localizations_*.dart`). Review `git diff` before
  committing them.
- `flutter/android/local.properties` and `gradle.properties` are generated and
  git-ignored. `local.properties` records the SDK path of whoever ran last
  (`/opt/flutter` in the container); Flutter rewrites it on the next run on
  either side.
- CMake (used by `audiopus_sys`/Opus) needs `ANDROID_NDK`; `docker-compose.yml`
  sets it. If you change the NDK version, update `ARG ANDROID_NDK` in the
  `Dockerfile` (it also drives `ANDROID_NDK_HOME`) and `ANDROID_NDK` in
  `docker-compose.yml`. The NDK Flutter expects is `flutter.ndkVersion` of the
  pinned Flutter; keep them in sync.

## Updating the toolchain

Edit the `ARG`s at the top of the `Dockerfile` (`FLUTTER_REF`,
`ANDROID_PLATFORM`, `ANDROID_BUILD_TOOLS`, `ANDROID_NDK`, `FRB_VERSION`) and
`ANDROID_NDK` in `docker-compose.yml`, then `docker/dev.sh build`. Keep
`FRB_VERSION` equal to `flutter_rust_bridge` in `flutter/pubspec.yaml`.

## Files

- `Dockerfile` — the image.
- `docker-compose.yml` — mounts, caches, host networking, `ANDROID_NDK`.
- `dev.sh` — wrapper: `build`, `shell`, `apk [debug]`, `install`, or any command.
