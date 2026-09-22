# myTeamSpeak — build plan (system A: login + bookmark/contact import)

> **After:** capture stop criteria met (`myteamspeak-research-plan.md` §2.4:
> login/session/bookmark/contact round trips decoded, blob-vs-cleartext
> decided, renewal path known).
> **Does not cover:** TS6 chat messaging (system B), 2FA enrollment, identity
> replacement (gated M5 only).
> **Hard rule:** no app milestone starts before its proto inputs are decoded.
> Language: code/comments/docs in English. User strings in
> `res/values/strings.xml` + `values-fr` + `values-it`.

## M0 — Deps, hygiene, skeleton (no network)

**Add to `gradle/libs.versions.toml` + `app/build.gradle.kts:145-164`:**

- `okhttp` (+ `logging-interceptor` for debug only), `kotlinx.serialization`
  (JSON; do NOT extend the hand-rolled bookmark JSON), `security-crypto`
  (EncryptedSharedPreferences/MasterKey), `androidx.browser` (only if capture
  shows an OAuth/authorize URL; else skip).
- `protobuf-java` (or `protobuf-kotlin-lite`) — version must match the
  `protoc` used to generate from reconstructed `.proto` files.

**Hygiene (same milestone):**

1. Ensure `captures/` is git-ignored (check `TS6_Droid/.gitignore`; mirror
   `../tslib/.gitignore` coverage) for `captures/myts/`.
2. Harden `BookmarkStore.parseBookmarks/serializeBookmarks`
   (`data/BookmarkStore.kt:97-129`): replace with `org.json` or
   `kotlinx.serialization` (current `split("},{")` breaks on `,:"` inside
   nicknames/passwords — unacceptable for untrusted import input). Keep the
   DataStore keys (`bookmarks_json`, `auto_reconnect`,
   `last_bookmark_address` at `:18-20`) unchanged.
3. Add `docs/proto/` with the reconstructed `.proto` + a
   `protoc --decode_raw` golden test for one captured bookmark payload
   (redacted).

**Accept:** `./gradlew assembleDebug` green; golden decode test passes.

## M1 — Session store + login (no sync yet)

**New files** (Kotlin-only, `data/` + `viewmodel/`):

- `data/MyTsSessionStore.kt` — modeled on `data/SettingsStore.kt:1`
  (per-domain store), but tokens in **EncryptedSharedPreferences**
  (Keystore MasterKey), never plaintext DataStore (both existing stores are
  unencrypted + `allowBackup="true"` in `AndroidManifest.xml:15` → add
  `backupRules` excluding tokens).
  Keys: `access/session token`, `renewal_token`, `otp_renewal_token`,
  `device_id`, `expires_at`, `username`. Exact set follows capture Q6.
- `bridge/MyTsApi.kt` — thin OkHttp client: base
  `https://clientapi.myteamspeak.com`, per-service paths, ProtobufRPC
  framing (`application/ts3cloud`) exactly as captured, no retry storms
  (≥4 s between manual replays).
- `viewmodel/MyTsViewModel.kt` — `login(email, password, otp?)` using
  `LoginData`/`AuthToken*`/`LoginSession` shapes; error mapping for
  `ERROR_AUTH_REQUIRES_OTP`, `ERROR_2FA_*`, 401/400 (forum shows flaky 400s —
  surface as retryable, not fatal).
- **UI:** `composable("myts_login")` in `ui/screen/AppNavigation.kt:12`
  (keep `"connection"` as start), entry from `ConnectionScreen` TopAppBar
  actions (`ui/screen/ConnectionScreen.kt:129`, title-only today) or a myTS
  button above the Bookmarks header (`:163-167`). Strings as `myts_*` in
  `strings.xml` (+ fr/it, `xml/locales_config.xml` unchanged).
- **Manifest:** add OAuth redirect `<intent-filter>` to `MainActivity` only if
  capture shows a browser authorize step; otherwise no manifest change beyond
  `backupRules`.

**Do NOT:** touch `identity.ini` (`ConnectionViewModel.kt:285`), bookmark
contents, or auto-reconnect (`:159-169`).

**Accept:** throwaway-account login succeeds; session survives process death;
logout wipes tokens; no token in logcat/plaintext backup.

## M2 — Read-only bookmark import (the first user value)

**Mapping** (`sync-protocol.md` §5): `Bookmark_Data{name,address,nickname,
server_password,default_channel,server_uid,…}` → `ServerBookmark`
(`data/ServerBookmark.kt:3`): name/address/nickname/password/channel.
Profiles (`capture/playback/hotkey/sound_pack`), `server_icon` (vs local
`iconId` enrichment via `updateServerInfo`), `phonetic_nickname`,
`resolved_server_nickname` → dropped + documented in import summary.

**Schema work first:** extend `ServerBookmark` (S4) with
`origin: LOCAL/MYTS`, `myTsUuid?` (`item_uuid`), `updatedAt?` — required for
merge/dedup and the optional per-item badge in
`ConnectionScreen.kt:177-254`. Match key: `server_uid` if present else
`address` (today: `address` only).

**Flow:** `MyTsViewModel.syncBookmarks()` =
`Sync_Request_ItemClasses{session,globalversion}` → per-item details →
protobuf decode (+ decrypt if capture Q4 says blobs — **if blobs, KDF
reimplementation is a sub-milestone here, with its own review**) → dedup
against `bookmarkStore.bookmarks.first()` → preview list → user confirms →
single `BookmarkStore.save(merged)` (`data/BookmarkStore.kt:38`, seam S1) →
existing Flow refreshes the list. Never clobber `last_bookmark_address`
(auto-reconnect interplay, `ConnectionViewModel.kt:150-169`).

**Accept (live, throwaway account):** 3 canary bookmarks import with
name/address/nickname/password/channel correct; re-import is a no-op (no
dupes); local-only bookmarks untouched; unit test covers mapping + dedup;
import summary states dropped fields.

## M3 — Legacy contact roster (greenfield store)

No local contact store exists — nothing to migrate.

- `data/MyTsContact.kt` (`mytsid` key, `customName?`, `customCategory?`,
  `chatRoomId?`, `notificationPref?`) + `data/ContactStore.kt` (new DataStore
  file `"myts_contacts"`, same pattern as `BookmarkStore` but with real JSON
  from day one).
- `MyTsViewModel.syncContacts()` via `class_contact_version_uuid` /
  `class_group_chats_version_uuid` cursors; folders: flatten as
  `Category/Name` display or keep `parent` tree — decide here (app bookmark
  list is flat; be consistent with the M2 folder decision).
- Read-only UI: a contacts section/route showing roster + online state
  **unavailable** (presence is system B) — label honestly as "roster".

**Accept:** canary contact round trip decodes; list shows `custom_name` +
category; re-sync no-op.

## M4 — Incremental sync + renewal (hardening)

- Persist `globalversion` + per-class version uuids (`Account_Data` cursors)
  in the session store; M2/M3 become incremental (capture Q7).
- Token renewal (`RenewalTokenLogin{renewal_token,auth_token}`,
  `otp_renewal_token`, `device_id`) on 401 + at startup; failure → explicit
  re-login state, never silent logout-and-wipe (lesson from the 2023-09
  myTS outage wiping local items: **local data is never deleted on sync
  failure**).
- Offline-first: sync is manual/pull-to-refresh + optional on-login; a failed
  sync leaves all local bookmarks/contacts intact with an error banner.

**Accept:** airplane-mode sync fails cleanly with data intact; expired-token
restart renews without re-entering password; version cursors advance.

## M5 — Gated: write-back + identity (explicit opt-in, default off)

Only after M2–M4 are stable. Each is a separate user-confirmed action:

1. Push local bookmark edits upstream (per-item `{item_uuid,item_version}`
   update; collision policy from `Item_Data.Manipulation_Flag` — TBD).
2. myTS identity import — **destructive** (changes server UID vs
   `identity.ini`): separate confirm screen, backup of `identity.ini` first,
   default **skip**. Never part of bulk import.

**Accept:** each action individually tested with canaries; default path
unchanged from M4.

## Test plan (all milestones)

- Unit: proto decode goldens (redacted captures), bookmark mapping/dedup,
  merge preview, cursor persistence. Reuse the `stream-capture` canary style:
  known `KNOWN-*` items asserted end to end.
- Integration (throwaway account only): login → import → re-import no-op →
  renewal restart → offline failure intact. Real account never used in tests.
- Manual: Wi-Fi + mobile data; 2FA-account login-with-OTP; server-password
  bookmarks (special chars `,:"` — regression for the M0 JSON fix).
- No-go: any milestone that deletes local data on cloud failure; any token in
  logs/backups; any identity overwrite without explicit confirm.

## Risks (top 4)

1. **Item encryption (Q4).** If payloads are KDF-wrapped blobs, M2 waits on
   KDF reversing (Ghidra on `setup_sync_account_using_auth_token` /
   `Item_Manager`). Budgeted as M2 sub-milestone, not a surprise.
2. **Undocumented rate limits / flaky 400/401s** (forum evidence). Mitigation:
   incremental sync, ≥4 s replay pacing, retryable-error UX.
3. **2FA on mobile.** Forum: logins with 2FA fail on TS3/mobile. Mitigation:
   support OTP field, document "disable 2FA or use OTP" limitation.
4. **ToS.** The cloud API is unofficial; behave like the desktop client
   (same endpoints, pacing, UA discipline) and keep traffic minimal
   (manual/incremental sync only).

## Ordering summary

`M0 hygiene → M1 login → M2 bookmarks → M3 roster → M4 incremental/renewal →
M5 (gated) write-back/identity.` System B (TS6 Matrix chat) is a separate
plan and must not leak into these milestones beyond the
`Chat_Credentials`/`TSCHAT_DE_Data` "do not touch" boundary.
