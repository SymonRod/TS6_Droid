# myTeamSpeak — research plan (static + capture)

> **Covers:** how to finish reversing the myTS cloud API. Companion:
> `myteamspeak-sync-protocol.md` (what is known), `myteamspeak-build-plan.md`
> (what to build once the wire is known).
> **Precedent:** `screenshare-research-plan.md` (method) +
> `screenshare-handoff.md` ("Re-running the capture" — FIFO/background-task
> harness; `captures/` never goes in git, already in `../tslib/.gitignore`).

## 0. Provenance (pin before each session)

```bash
ls -l /opt/teamspeak/TeamSpeak /opt/teamspeak/libtschat_client_lib_export.so \
  /opt/teamspeak/html/client_ui/main.js
md5sum /opt/teamspeak/TeamSpeak \
  /opt/teamspeak/libtschat_client_lib_export.so \
  /opt/teamspeak/html/client_ui/main.js
file /opt/teamspeak/TeamSpeak /opt/teamspeak/libtschat_client_lib_export.so
```

Record sizes + MD5s at the top of every evidence note. Reference build for
everything below: desktop client dated 2025-07-13 (66 MB `TeamSpeak` ELF
stripped, 20 MB Go `libtschat_client_lib_export.so`, 9.7 MB `main.js`).
Pinned 2026-09-09: `TeamSpeak` 66365272 B md5 `8234f961015da34f1387fa735a7443b0`,
`libtschat_client_lib_export.so` 20326736 B md5 `c80d95c7e850739d9de29d3d37cbf025`,
`main.js` 10080350 B md5 `ab4fd33a8e1fa31561bafa11f5401ba1`.
`pbtk` not installed; `protoc` 36.1 available (via-1 blocked, via-2 ready).

## 1. Phase 1 — static analysis (done 2026-09-22 except 1D)

All commands are read-only. Prefer `strings -n 6/8 … | grep -a … | sort -u`.

### 1.1 Endpoints (done — verify, don't redo)

```bash
strings -n 8 /opt/teamspeak/TeamSpeak \
 | grep -aE "https://.*myteamspeak|https://.*teamspeak\.com/[a-z]+" | sort -u
```

Expected (20 unique): `api.teamspeak.com/lookup`,
`badges-content…/list`, `blacklist2…/check`,
`clientapi.myteamspeak.com/{addon,authentication,integration,management,messenger,session,synchronization,tschat,user}`,
`named.myteamspeak.com/`, `ts3services…/{revocation-certificates,revocation-myteamspeakid,static_integration_info}`,
`www.myteamspeak.com[/api]/`, `desktop-client.teamspeak.com`,
`teamspeak.com/specs/extensions.scheme.json`.
**Open question:** which of these the Android-equivalent flow actually needs
beyond `authentication`/`session`/`synchronization` (+ `user` for
`UserAccountData`). Answer in Phase 2 by observing call order.

### 1.2 Sync schema (done 2026-09-22 — recovered into `docs/proto/`)

```bash
strings -n 6 /opt/teamspeak/TeamSpeak | grep -a "com.teamspeak.sync.proto" | sort -u
strings -n 6 /opt/teamspeak/TeamSpeak \
 | grep -a "com.teamspeak.myteamspeak.proto.synchronization" | sort -u
strings -n 6 /opt/teamspeak/TeamSpeak \
 | grep -a "com.teamspeak.account.proto" | sort -u
```

Known payloads (12 classes): `Bookmark_Data`, `Identity_Data`, `Contact`,
`Group_Chats`, `HotkeyProfile_data`, `Whisper_list_data`, `Add_on_data`,
`Config_data`, `Item_Folder`, `Chat_Credentials`, `TSCHAT_DE_Data`,
`item_room_category` (name from version uuid only — no `sync.proto` message
string seen; likely server-side or inside `Item_Data`).

**Task 1A — done 2026-09-22.** The descriptors are serialized
`FileDescriptorProto`s, so they carry numbers, types and labels too —
`docs/proto/extract_descriptors.py` does route 1 below without `pbtk` and
verifies a protoc round trip. Original plan kept for the record: The descriptor blobs
give names in field order but not numbers. Two routes, try in order:

1. `pbtk` extractors on the binary (protobuf reflection metadata is present —
   `Google.Protobuf.Reflection`, `myteamspeak_synchronization.pb.cc`
   path strings observed). If `pbtk` yields `.proto` files, verify field names
   against §2 blobs.
2. Manual: capture (Phase 2) + `protoc --decode` with a hand-written schema,
   iterating on tag mismatches. The blobs give field *order*, which usually
   matches tag order for these generated files.

**Task 1B — done 2026-09-22:** `Item_Class` values are in
`synchronization_common.proto` (`BOOKMARK=0` … `CONTACTS=8`). Original note: No string labels found
(values travel as ints; `static_cast<sync::Item_Type>(…)`, assert
`type != Item_Type::unknown`). Inventory via the 10 per-class version uuids in
`Account_Data` (`class_{bookmark,identity,add_on,config,hotkey_profile,
whisper_list,item_folder,item_room_category,group_chats,contact}_version_uuid`).
Map int→class in Phase 2 by requesting one class at a time.

### 1.3 Auth/session schema (done 2026-09-22 — recovered into `docs/proto/`)

```bash
strings -n 6 /opt/teamspeak/TeamSpeak \
 | grep -aoE "com\.teamspeak\.myteamspeak\.proto\.[A-Za-z0-9_.]+" | sort -u
```

Notable top-level messages already inventoried:
`AuthToken{id,mytsid}`, `AuthTokenRequest{email,password}`,
`AuthTokenLogin{auth_token,device_description}`, `AuthTokenReply{auth_token}`,
`LoginData{email,password,otp,device_id,otp_renewal_token,device_name}`,
`LoginSession{session,uuid,username,push_token,
AlternativeLoginInformation{renewal_token,otp_renewal_token,device_id}}`,
`RenewalToken{token}`, `RenewalTokenLogin{renewal_token,auth_token}`,
`Session{session}`, `LoginStatus{uuid}`.
**Negative result (verified):** no `…myteamspeak.proto.authentication.*` or
`…session.*` sub-package — auth/session are top-level messages. Do not go
looking for them.

**Task 1C — done 2026-09-22:** the service descriptors give every RPC with
its service (`LoginService`, `SynchronizationService`,
`UserAccountService`, …; `getKey` is admin-only `UserManagementService`),
and the request framing (`u8 len + method name + protobuf`) was
disassembled from `teamprotobufrpc` — see sync-protocol §0. Original note: Known sync verbs (static 2026-09-09):
**`requestServerItems` AND `synchronizeItems`** (both `Method …() not
implemented.` stubs) + `Closure<Sync_Request_ItemClasses,
Sync_Reply_ItemClasses>` + `Sync_Client_Lib_Impl::{m_sync_start, m_sync_items,
compare_sync_remote}`. Which verb goes on the wire is a Phase-2 question.
Auth/session stubs: `login()`, `loginWithAuthToken()`,
`loginWithRenewalToken()`, `session()`, `getBackupKey()`, `getKey()`
(service mapping not recoverable statically — stubs carry no service).
Two client-side flows distinguished by message shape (not URL adjacency):
flow A session (`LoginData` → `LoginSession`) vs flow B token
(`AuthTokenRequest` → `AuthTokenReply` → `AuthTokenLogin`, renew via
`RenewalTokenLogin`, sync entry via `setup_sync_account_using_auth_token`).
Extract/confirm via:

```bash
strings -n 6 /opt/teamspeak/TeamSpeak \
 | grep -aE "request[A-Z][A-Za-z]+|Method [a-zA-Z]+ *\(\)" | sort -u | head -100
```

cross-referenced with `MyTeamSpeak::Account::*` symbols
(`loginAccount`, `generate_otp_setup_secret`, `confirm_two_factor_auth_type_otp`,
`setup_sync_account_using_auth_token`, …) and `main.js` bridge names
(`loginAccount`, `getMytsAccountState`, `applySyncableItemActions`,
`setSyncEnabledState`, … — `main.js` never touches `clientapi` directly, so it
only names the bridge, not the wire).

### 1.4 Encryption / recovery key (least known — highest risk)

Known fragments:

- `TS_Sync_Account{passphrase}`, `Auth_Token_Package{auth_token,
  encrypted_encryption_password, encryption_tag, iv}` (AEAD shape: iv + tag).
- `Assertion "!salt.empty()"` (`teamcloud_sync_client_lib/Item_Manager.cpp`),
  `channel_security_salt`, `decrypted_user_private_key`.
- UI strings: `Requesting use recovery key`, `Failed to request new recovery
  key:`, `confirmed_recovery_key` (×18 in `main.js`); **no** passphrase
  generator UI strings — key derivation is native.
- Cipher noise: `AEAD_AES_128_GCM` / `AEAD_AES_256_GCM` (+ OpenSSL tables),
  `Encryption_Impl` + **`Encryption_Impl_V2`**, vendored
  `teamcrypto/.../libtomcrypt/...` (aes, eax, sha2, ctr, omac), assert
  `"plain_hash.size() == teamcrypto::sha2::sha512_size" (Encryption.cpp)`.
  `pbkdf|hkdf` = 0 hits; `scrypt|argon` = only vendored OpenSSL provider
  paths (`crypto/evp/pbe_scrypt.c`, `kdf_argon2_ctx_set_salt`) — **no
  app-level KDF call found** (static 2026-09-09). Backup-key sidecar:
  `Closure<UserLogin,BackupKeyData>` + `m_request_backup_ed_key_binder
  (UserLogin→BackupKeyData)`, UI `BackupKey` / 44-char check /
  `confirmed_recovery_key` ×18.

**Remaining task 1D — key derivation (the only open Phase-1 item).**
Known inputs now have field numbers (sync-protocol §7). Strings are
exhausted; the next step is disassembling `Encryption_Impl_V2` and
`Item_Manager` (anchor: the `!salt.empty()` / `plain_hash.size()` assert
strings) — or let capture Q4 show first whether `item_blob` is opaque. Look for KDF markers near the sync
symbols before capturing:

```bash
strings -n 6 /opt/teamspeak/TeamSpeak \
 | grep -aiE "pbkdf|scrypt|argon|hkdf|sha256|recovery" | sort -u | head -50
```

Hypothesis to confirm/deny in Phase 2: item payloads are per-item encrypted
blobs decrypted with a key derived from the recovery key (passphrase) + salt;
`Auth_Token_Package` carries the wrapped encryption password. If mitmproxy
shows opaque blobs after login, this is confirmed and the KDF becomes the
critical path (may require decompiling `setup_sync_account_using_auth_token`
/ `Item_Manager` — budget for Ghidra time).

### 1.5 What NOT to spend time on

- `libtschat_client_lib_export.so` for sync: 0 hits on all `sync.proto` /
  `synchronization` / `myteamspeak.proto` patterns. Its only myTS URL is the
  Matrix push gateway `push.teamspeak.com/_matrix/push/v1/notify`. Skip it for
  system A.
- `searchUser` in `main.js`: 0 hits — user lookup is the
  `contactIdentifierSuggestion` flow, not a search API.
- `ChatCredentials` in `main.js`: 0 hits — credentials stay in C++/Go. Any
  chat follow-up must capture the native layer, not the JS.

## 2. Phase 2 — live capture (the decision procedure)

### 2.1 Setup: mitmproxy in front of the desktop client

The cloud API is plain HTTPS POST (ProtobufRPC, `application/ts3cloud` —
see forum captures of `POST …/synchronization`, 1120 B bodies, `cpp-httplib`
UA). No voice-protocol hook applies; intercept at TLS.

```bash
# 1. Install mitmproxy, generate CA, trust it in the system store,
#    then run the desktop client with proxy env:
export HTTPS_PROXY=http://127.0.0.1:8080 HTTP_PROXY=http://127.0.0.1:8080
mitmproxy --mode regular --listen-port 8080 -w captures/myts/session-1.mitm
/opt/teamspeak/TeamSpeak  # log in, toggle sync, add a bookmark/contact
```

- If the client pins certs or ignores env proxy (likely for a C++ client —
  **unverified**), fall back in order: (a) `LD_PRELOAD` proxy shim /
  `proxychains`, (b) transparent mode with iptables redirect, (c) Frida hook
  on the `ProtobufRPC` post function (`Error contacting URL %s` format string
  is a good anchor — it prints the URL on failure).
- Account hygiene: use a **throwaway myTS account** with 2–3 known bookmarks
  (`KNOWN-BOOKMARK-1…`) and one known contact; never capture the real account.
  `captures/myts/` carries tokens — same redaction rule as
  `screenshare-handoff.md`: raw stays local, only redacted excerpts in docs.
- Drive deterministically, one action per run: (1) fresh login, (2) login with
  OTP if available, (3) sync with no changes, (4) add bookmark → sync,
  (5) add contact → sync, (6) token-renew path (restart client offline→online).

### 2.2 What to record per run

For each HTTPS exchange: endpoint path, request/response sizes, raw bodies
saved to `captures/myts/<run>-<seq>.{req,resp}.bin`, plus client log lines
(`ProtobufRPC`, `sync_event, account status change`, `failed to initialize
encryption`, … — cf. forum log samples). Goal table:

| # | Question | Answered by |
|---|---|---|
| Q1 | Auth call order + method/message names (login → session → token?) | **run6 partial**: `session`/`deleteSession` on `/authentication` seen; full `login` not exercised (profile already logged in) |
| Q2 | Sync framing: headers, `requestServerItems` verb, `Sync_Request_ItemClasses{session, globalversion}` encoding | **run6 ANSWERED**: framing `u8 len+method+protobuf`; `requestServerItems` pulls, `synchronizeItems` pushes |
| Q3 | Per-class item fetch: how `item_uuid/item_version` detail requests map to `Bookmark_Data` / `Contact` payloads | **run6 partial**: request cursors seen; pull-reply blobs mis-correlated in the startup burst (tool limit) |
| Q4 | Encryption: are payloads opaque blobs? Which KDF/salt/iv/tag? | **run6 ANSWERED (blob side)**: `item_blob` is encrypted (~7.5 bits/B, no `Item_Data` parse). KDF family/salt/iv still open → 1D |
| Q5 | 2FA behavior: `otp` field use, `ERROR_AUTH_REQUIRES_OTP` trigger | run 2 (only if a test account with OTP exists) |
| Q6 | Token renewal (`RenewalTokenLogin`, `otp_renewal_token`, `device_id`) | run 6 (not yet observed) |
| Q7 | `globalversion` semantics (incremental vs full sync) | **run6 partial**: each `synchronizeItems` push returns a new `globalversion` (looks incremental) |

Pace requests like the screenshare probes if replaying manually — flood
protection (`error id=524`, 10 s lockout) is a voice-server mechanism, but the
cloud API rate-limits too (forum 400/401 flakiness); keep replays ≥4 s apart.

### 2.3 Decoding loop

```bash
# Raw protobuf inspection without schema:
protoc --decode_raw < captures/myts/<run>-<seq>.resp.bin | head -80
# With reconstructed schema (from 1A):
protoc --proto_path=docs/proto --decode=com.teamspeak.sync.proto.Bookmark_Data \
  sync.proto < payload.bin
```

Iterate: field order from the descriptor blobs usually matches tag order; tag
mismatches show as wrong wire types — fix and re-decode. Promote every decoded
message into `myteamspeak-sync-protocol.md` § tables with a captured hex
prefix + field table (same evidence standard as `screenshare-protocol.md`
§9a.3/§9b).

### 2.4 Stop criteria (when capture is "done")

- Q1–Q3 answered with decoded bodies for login, session, one bookmark round
  trip, one contact round trip.
- Q4 answered at least to "blob vs cleartext + which KDF family" — full KDF
  reimplementation is build-phase work (M2), not capture work.
- Q6 answered to "which token to store + when to renew".
- Q5/Q7 nice-to-have; do not block the build on them.

## 3. Evidence handling

- `captures/myts/*.mitm`, `*.bin` — **never commit** (extend
  `../tslib/.gitignore`-style coverage: check `TS6_Droid/.gitignore` covers
  `captures/`; if not, add it in M0).
- Docs carry only: endpoint paths, message/field names, redacted field tables,
  short hex prefixes (≤32 B), and error strings. No tokens, emails, salts,
  `mytsid`s, or public IPs.
- Each protocol-doc table cites its source run (`session-1`, req seq) like the
  screenshare doc cites §9a/§9b sessions.
