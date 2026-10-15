# Flutter file browser (list + download) plan

Goal: browse channel files and download them from the Flutter app, reusing the
Rust `tslib-core` file transfer implementation. Read-only first (list +
download); write operations (upload, delete, rename, mkdir) are an explicit
follow-up, not part of this delivery.

## Current state (2026-10-15)

| Layer | State |
|---|---|
| `tslib-core` (`../ts6-lib`, separate repo) | Complete: `list_files`, `download_file`, `upload_file`, `delete_file`, `rename_file`, `create_directory` (`crates/tslib-core/src/client.rs`), events `FileListReceived`, `FileDownloaded`, `FileUploaded`, `FileTransferFailed` (`crates/tslib-core/src/events.rs`) |
| `tslib-frb` bridge | Only `download_file` exposed (`crates/tslib-frb/src/api.rs:581`) plus `FileDownloaded` / `FileTransferFailed` events. `FileListReceived` and `FileUploaded` fall into `_ => return None` in `conv_event` and never reach Dart |
| Flutter app | No file UI. `server_screen.dart` has channels + chat tabs only. `downloadFile` is used internally by `lib/src/state/server_controller.dart` for icons/avatars (channel 0, `/icon_*`, `/avatar_*`) |
| Kotlin reference | Full manager: `TsClient.kt:323,344,364,368,372,398` + `FileManagerDialog.kt:74` + `ServerViewModel.kt` (`refreshFileList`, `navigateToFolder/Up`, `downloadFileFromManager`, permission hints) |

Stale-path debt (fix inside this plan, step 0): the Flutter build points at
`../../tslib`, which does not exist on this machine (`flutter_rust_bridge.yaml`
`rust_root`, `flutter/android/app/build.gradle.kts` `rustProjectDir`
resolving to `/home/rod/develop/tslib`). The real checkout is
`/home/rod/develop/ts6-lib`.

## Decisions

- Reuse `tslib-core` as-is; add only FRB surface, no protocol work.
- Phase A (this plan): `list_files` + `download_file` + `FileListReceived`
  event. No upload/delete/rename/mkdir in the UI.
- Keep the core 10 MB download cap (`client.rs` download path); surface a
  clear error above it instead of raising the cap here.
- File scope = current channel, paths shaped like Kotlin (`/` root,
  `currentPath + name`, folders end with `/`).
- Browse/download gated by existing `TsChannel.permission_hints` (same rule as
  `FileManagerDialog.kt`: hide nothing for browse, toast on `CommandError`
  denial).
- Downloaded bytes go to the app cache dir (same pattern as `ts_images` in
  `server_controller.dart`), then opened/shared via a platform share/open
  intent; no new native file provider beyond what the Kotlin `FileCache` +
  `openFileUri` already demonstrates.
- New strings go in `.arb` (en + fr + it), not hardcoded.

## Steps

### 0. Fix Rust checkout paths (TS6_Droid repo)

- Point `flutter/flutter_rust_bridge.yaml` `rust_root` and
  `flutter/android/app/build.gradle.kts` `rustProjectDir` at the real
  checkout (`../../ts6-lib`), keeping the `symbols/frb/` copy logic.
- Exit check: `flutter_rust_bridge_codegen` resolves and the Gradle
  `buildRust`-adjacent task finds `Cargo.toml`.

### 1. Expose listing in `tslib-frb` (ts6-lib repo, commit there first)

- Add `TsFileEntry { name, size, datetime, is_file }` + `conv_file` mirroring
  `FileEntry` (`client.rs:38`).
- Add `TsClient::list_files(channel_id: i64, path: String)` calling
  `client.list_files` (same thin wrapper shape as `download_file`).
- Add `TsEvent::FileListReceived { channel_id, path, files }` and its
  `conv_event` arm; leave `FileUploaded` out (phase B).
- Add/extend offline Rust tests: empty dir, flat list, `FileListFinished`
  without pending request (must not crash, cf. `client.rs` warn paths).
- Exit check: `cargo test -p tslib-frb` (and core file tests) green.

### 2. Regenerate bindings and build

- Run `flutter_rust_bridge_codegen`, check in regenerated
  `flutter/lib/src/rust/*`.
- Build the `.so` via the Gradle task; confirm `download_file` still works
  (avatars/icons load, no regression).
- Exit check: `flutter analyze` clean, debug APK builds.

### 3. Dart state (no clash with avatar downloads)

- New `FileManagerState` (separate notifier, not inside the avatar
  `_imageInFlight` map): `channelId`, `currentPath`, `entries`, `loading`,
  `error`.
- Correlate `FileListReceived` by `(channel_id, path)`; ignore stale arrivals
  after `navigateToFolder/Up` or channel switch (Kotlin uses the same
  `"$channelId:$path"` key in `listFiles`).
- Keep avatar/icon `FileDownloaded` routing untouched (`_keyForPath`); route
  manager downloads by pending path set owned by the new notifier.
- Timeouts mirror Kotlin: ~5 s list, ~10-30 s download; `CommandError`
  surfaces via existing `serverProvider` error toast.
- Exit check: Dart unit tests with a fake event stream (list success, empty
  dir, stale-event drop, transfer failure).

### 4. UI

- Entry point: channel-row overflow or `_ControlBar` "more" sheet (match
  Kotlin `toggleFileManager` affordance), opening a `FileManagerScreen`.
- Screen: path bar, back navigation, refresh, folder/file rows (folders first,
  alphabetical, size + date like Kotlin), tap folder to enter, tap file or
  download icon to fetch.
- Download flow: progress indicator, save to cache, then system share/open
  sheet; failure shows `CommandError`/timeout text.
- Strings: `app_en/fr/it.arb` additions only.
- Exit check: manual pass on a real server (nested folders, empty dir, denied
  channel, >10 MB file shows the cap error).

### 5. Verification and docs

- Real-phone check against a server with files (Wi-Fi): list, enter folder,
  back, refresh, download + open.
- Update `docs/flutter-migration-plan.md` phase 6 row (file manager started /
  read-only done) and close this plan doc.

## Explicitly out of scope (phase B)

Upload, delete, rename, mkdir, chat `ts3file://` attachments
(`ServerViewModel.kt:463,576,612`), `FileUploaded` FRB event, raising the
10 MB cap, and any background-transfer persistence.

## Risks

- Avatar `FileDownloaded` traffic shares one event stream with manager
  downloads: demultiplex by owner (avatar keys vs manager pending set), never
  by timing.
- Two repos: land the `tslib-frb` change in `ts6-lib` first, then bump/verify
  from `TS6_Droid`; do not half-land the Dart side against an unreleased API.
- Large files are fully buffered (`Vec<u8>`); the cap error must be user
  readable, not a silent spinner.
