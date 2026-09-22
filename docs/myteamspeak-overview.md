# myTeamSpeak integration — overview

> **Status:** plan. No app code changes yet.
> **Goal:** log in with a myTeamSpeak account in TS6 Droid and import/sync
> bookmarks + contacts.
> **Method:** same as screen sharing (static analysis of the desktop client +
> live capture), but the target is the **HTTPS cloud API**, not the voice
> protocol. No Rust/`tslib` fork is needed.
> **Map:** `myteamspeak-research-plan.md` (how to reverse) →
> `myteamspeak-sync-protocol.md` (schema reference) →
> `myteamspeak-build-plan.md` (what to write, in what order).

## 1. The two "contacts" systems (do not conflate)

| # | System | Transport | What you get | Cost |
|---|---|---|---|---|
| A | **Legacy sync** (`synchronization`) | `POST https://clientapi.myteamspeak.com/synchronization`, `Content-Type: application/ts3cloud`, ProtobufRPC | Bookmarks, identities, **contact roster** (`Contact{mytsid, custom_name, custom_category}`), hotkeys, whisper lists, folders. The *address book*. | One protobuf sync task. **This plan covers it.** |
| B | **TS6 chat** (`tschat` + Matrix) | `…/tschat` control plane + Matrix data plane via homeserver + libolm E2E | Chat identity (`ts_chat_identifier ↔ matrix_id`), rooms, messages, presence. The *person*. | A full Matrix+olm client (~70 `TSChat_*` exports in `libtschat_client_lib_export.so`). **Explicitly out of scope**; see §5. |

A synced roster (A) does not give messaging ability. Do A first; B is a
separate project.

## 2. Key findings from static analysis (2026-09-09)

Binary: `/opt/teamspeak/TeamSpeak` (66 MB, stripped ELF), build 2025-07-13.
Full inventory lives in the research plan; the load-bearing facts:

- Sync/cloud code lives in the `TeamSpeak` binary (`teamcloud_sync_client_lib`,
  `Sync_Client_Lib_Impl`, `Account_Manager_Impl`), **not** in
  `libtschat_client_lib_export.so` (Go Matrix client, zero `sync.proto` hits).
- The CEF UI (`html/client_ui/main.js`) never calls `clientapi.*` directly
  (0 hits) — it goes through the native bridge (`tsclient_internal`,
  `tschat_manager`). Capture must target the native layer's HTTPS, not the JS.
- Protobuf reflection strings are embedded in clear: `sync.proto` field blobs
  (`Bookmark_Data`, `Contact`, `Identity_Data`, …), `synchronization.*`
  wrapper messages, and top-level auth messages (`LoginData`, `LoginSession`,
  `AuthToken*`, `RenewalToken*`) are all recoverable without decompilation.
- Per-service endpoint split mirrors the proto packages:
  `/authentication`, `/session`, `/synchronization`, `/user`, `/tschat`,
  `/messenger`, `/integration`, `/addon`, `/management`.

## 3. Architecture decision

- **Kotlin-only module** (`data/MyTs*`, new `MyTsViewModel`). The cloud API is
  HTTPS + protobuf; there is nothing for `tsclientlib`/`tslib-core`/JNI to do.
  No `Messages.toml` / `Book.toml` fork work, unlike screen sharing.
- New deps via the version catalog (`gradle/libs.versions.toml`), not inline:
  `okhttp`, a JSON lib (`kotlinx.serialization`), `security-crypto`
  (EncryptedSharedPreferences), `androidx.browser` (Custom Tabs if OAuth is
  used — TBD in capture).
- Write path into the existing store: bulk import via
  `BookmarkStore.save()` (`app/src/main/kotlin/dev/tsdroid/data/BookmarkStore.kt:38`),
  so the existing `bookmarks` StateFlow → `ConnectionScreen` list refreshes
  with zero list-UI changes. Contacts have no local store — greenfield.
- Secrets (tokens, server passwords already in `bookmarks_json` plaintext)
  move to encrypted storage; see the build plan.

## 4. Current app seams (exact)

- Model: `data/ServerBookmark.kt:3` — no uuid/origin/timestamp; match key is
  `address`.
- Storage: `data/BookmarkStore.kt:13` (DataStore file `"bookmarks"`, hand-rolled
  JSON at `:97-129`, fragile on `,:"` — must harden before importing
  untrusted strings).
- Identity: single `identity.ini` in `ConnectionViewModel.getOrCreateIdentity()`
  (`viewmodel/ConnectionViewModel.kt:285`) — importing a myTS identity would
  change the server UID; destructive, needs explicit opt-in (default: skip).
- Nav: `ui/screen/AppNavigation.kt:9` (`"connection"` → `"server"`, string
  routes) — add `"myts_login"`.
- Settings pattern to copy: `data/SettingsStore.kt:1` (per-domain DataStore
  file + typed keys).

## 5. Non-goals (this plan)

- TS6 chat messaging, presence, rooms, E2E (system B). The roster from sync is
  the stopping point; any chat work gets its own plan.
- myTS identity *replacement* (import is read-only analysis only; write path
  explicitly gated behind a later milestone).
- 2FA enrollment flows. Login must *tolerate* OTP (`LoginData{email,password,
  otp,…}` exists) but enrollment UI is out of scope; forum evidence says
  mobile/TS3 logins with 2FA enabled fail, so the plan treats 2FA as
  login-with-OTP-only.
- Server-side or upstream work. No TeamSpeak cooperation is assumed.

## 6. Document map

1. `myteamspeak-research-plan.md` — Phase 1 (finish static extraction) +
   Phase 2 (mitmproxy capture recipe, incl. background-task harness reuse from
   `screenshare-handoff.md`) + what counts as evidence.
2. `myteamspeak-sync-protocol.md` — schema reference as known today; the
   capture fills the framing/encryption gaps. This file supersedes the others
   on wire details once capture lands.
3. `myteamspeak-build-plan.md` — milestones M0–M5: deps → session store →
   read-only bookmark import → contacts roster → (gated) write-back/identity.
   Order, acceptance criteria, risks, and test plan.
