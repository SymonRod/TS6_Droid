# myTeamSpeak — sync protocol reference (system A)

> **Contacts/chat update (2026-10-15):** the authorized demo-account probe
> returned one account contact from `/tschat/getContactList` while sync
> `CONTACTS=8` and `GROUP_CHATS=7` were empty. CONFIG supplied chat credentials;
> `/user` returned four avatar variants and signed download URLs. The account's
> Matrix host returned HTTP 503 through both the gateway and a public phone
> cellular probe, so messages, history and
> live presence are not yet verified. See
> [myteamspeak-contacts-chat-protocol.md](myteamspeak-contacts-chat-protocol.md).
> Historical “never touch”/out-of-scope System-B wording below is not a permanent
> product restriction; it is not authorization for speculative cloud writes.

> **Product policy (2026-10-14):**
> [product-direction.md](product-direction.md) supersedes historical manual-only
> identity-import/M5 policy below. Automatic identity + bookmark import is
> required on fresh-app myTeamSpeak sign-in, with protection for existing local
> data. This changes product policy, not the schemas or system A/B boundary.

> **Offline item update (2026-10-14):** all five run41b bookmarks are now
> independently decrypted and integrity-checked, with exact native equality.
> Item format: `IV[16] || AES256-CTR-128LE(account_key, plaintext) ||
> SHA512(plaintext)[64]`, **no version byte or extra KDF**. The digest is
> unkeyed, not a MAC/AEAD guarantee. See the
> [bookmark/item reference](myteamspeak-bookmark-decryption-protocol.md) for
> provider trace, eight-item evidence and synthetic/Rust tests. Flutter import,
> account-key lifecycle and renewal remain separate; older unresolved claims
> below describe their historical research state.

> **Run41 update (2026-10-14):** version-2 `LoginSession.key` unwrap is now
> demonstrated: [account-key reference](myteamspeak-key-unwrap-protocol.md).
> The remaining critical path is the account-key-to-item decrypt/integrity
> chain, not another password-KDF or account-key guessing round. Historical
> statements below about unresolved account unwrap describe earlier runs.

> **Login update (2026-10-14, run40):** see
> [myteamspeak-login-protocol.md](myteamspeak-login-protocol.md) for the
> demonstrated password KDF, request/reply fields and successful standalone
> login. It supersedes historical login/KDF uncertainty below. The old-build
> schemas/offsets in this document remain historical; sync key unwrap is still
> unresolved. Flutter is the current implementation target.

> **Status:** Phase-1 static analysis complete; Phase-2 capture done for the
> login/sync/user/tschat closure (run6, 2026-09-22, client build 2025-07-13).
> Schemas are **recovered, not inferred**: the binary embeds every
> `FileDescriptorProto`, extracted and round-trip verified into `docs/proto/`
> (see its README). Field numbers, types, enum values and RPC names below come
> from there; `docs/proto/*.proto` is the source of truth for that older-build
> schema snapshot. Current-build login additions and live validation are
> documented in `myteamspeak-login-protocol.md`.
> STATIC = derived from the binary, not yet seen on the wire.
> CONFIRMED (run6) = observed on the wire by the in-process gdb capture
> (`tools/myts/gdb_capture.py`, plaintext read before TLS, secrets masked).
> TBD/HYPOTHESIS = not yet known.
> **Capture verdict: item payloads are encrypted** (§7, capture Q4). Run40
> solved login and the account encryption-value KDF; account-key/item unwrap
> remains the critical path for sync (M2+).

## 0. Transport

- Base `https://clientapi.myteamspeak.com`, path-per-service (§1).
- Every call is one HTTPS `POST`, `Content-Type: application/ts3cloud`
  (CONFIRMED run6: the content-type arg is the 20-byte `application/ts3cloud`),
  `User-Agent: cpp-httplib/0.11.1` (forum captures).
- **Request body (CONFIRMED run6; disassembled 2026-09-22):**

  ```
  u8   n                       method name length (< 128, else the call aborts)
  n B  method name             simple name, e.g. "session", "requestServerItems"
  ...  request message         plain protobuf serialization, no length prefix
  ```

  Source: `com::teamspeak::rpc::Channel` (vtable slot 2 `CallMethod` @
  `0x1dff8e0` → worker @ `0x1dfd410`): reserve 1024 B, `append(1, len)`,
  `append(MethodDescriptor::name())` (protobuf 32 `DescriptorNames` index 0,
  i.e. the simple name, not `full_name`), `IsInitialized()`,
  `AppendToString(request)` (failure → `"Error serializing protocol
  buffer"`). The service is not in the body — it is the URL path.
  Confirmed on the wire at the cpp-httplib POST call (`0x1dfd82a`,
  `call [rax+0x18]`): args are `rsi` = URL, **`rcx` = body** (the framed
  `std::string` above), `r8` = content type. (The earlier handoff note of
  `rdx`/`r9` for body/response was wrong — `rdx` is empty at that site.)
- **Response body (CONFIRMED run6):** on HTTP 200 the whole body goes to
  `response->ParseFromString()` (`0x1dfde0b`, `rsi` = data, `rdx` = length),
  no envelope. Non-200 → the controller fails with the status code.
  Application errors travel inside the reply messages (`ErrorCommon`,
  `SyncStatus`, `ReturnCode`).
- Service → path (CONFIRMED run6 for the five in **bold**; others HYPOTHESIS
  by name): **`LoginService` → `/authentication`** (`session`,
  `deleteSession`), **`SynchronizationService` → `/synchronization`**
  (`requestServerItems`, `synchronizeItems`), **`UserAccountService` →
  `/user`** (`getSignedBadges`, `getTwoFactorAuthType`, `requestContactsAvatar`),
  **`IntegrationUserService` → `/integration`** (`getIntegrationUserStatus`),
  **`ChatRequests` → `/tschat`** (`getActiveIdentifierList`,
  `getAllowedIdentifierList`, `getContactList`,
  `requestSignedAllowedIdentifierList`); `UserAddonService` → `/addon`,
  `MessengerConnectorClientService` → `/messenger`, `UserManagementService` →
  `/management` (admin/back-office, never called by a normal client — `getKey`
  lives here, not in the login flow) not yet observed. `/session` has no
  matching service in the descriptors — TBD.
- Sync lib symbols: `Sync_Client_Lib_Impl::{m_sync_start, m_sync_items,
  compare_sync_remote}`, `ICloud_Sync` / `Cloud_Sync_Impl`,
  `Account_Requestor_Cloud_Sync`; per-service `…_Requester_Protobuf_Rpc`.
- UI never calls the cloud directly (`main.js`: 0 `clientapi` hits) — all
  traffic comes from the native layer.

## 1. Endpoints (complete, sorted — from binary)

```
https://clientapi.myteamspeak.com/addon
https://clientapi.myteamspeak.com/authentication
https://clientapi.myteamspeak.com/integration
https://clientapi.myteamspeak.com/management
https://clientapi.myteamspeak.com/messenger
https://clientapi.myteamspeak.com/session
https://clientapi.myteamspeak.com/synchronization
https://clientapi.myteamspeak.com/tschat
https://clientapi.myteamspeak.com/user
```

Supporting: `https://named.myteamspeak.com/`,
`https://www.myteamspeak.com[/api]/`, `https://api.teamspeak.com/lookup/`,
`https://ts3services.teamspeak.com/{revocation-certificates,
revocation-myteamspeakid,static_integration_info}`,
`https://badges-content.teamspeak.com/list`,
`https://blacklist2.teamspeak.com/check`.
Go chat lib only: `https://push.teamspeak.com/_matrix/push/v1/notify`
(system B data plane; not sync).

## 2. Auth / session (`myteamspeak_login.proto`, `myteamspeak_common.proto`)

**Current implementation reference:**
[myteamspeak-login-protocol.md](myteamspeak-login-protocol.md). Password login
now has a demonstrated KDF and successful standalone test. The table below
is the older committed-schema snapshot; the new build additionally declares
recovery fields/errors. It is not a specification for a separate auth-token
preflight before ordinary password login.

`LoginService` (package `…proto.login`), request → reply types in
`…myteamspeak.proto` unless noted:

| RPC | Request | Reply |
|---|---|---|
| `login` | `LoginData` | `LoginSession` |
| `requestAuthToken` | `AuthTokenRequest{email=1, password=2}` | `AuthTokenReply{auth_token=1, error=3}` |
| `loginWithAuthToken` | `AuthTokenLogin{auth_token=1, device_description=2}` | `LoginSession` |
| `loginWithRenewalToken` | `RenewalTokenLogin{renewal_token=1, auth_token=2}` | `LoginSession` |
| `session` / `deleteSession` | `Session{session=1}` | `LoginStatus{error=1, uuid=2}` |
| `getAuthTokenList`, `expireAuthTokenAccess` | `login.AuthToken{List,Expire}Request{email, password, …}` | device list / success |
| `deleteAccount`, `suspendAccount`, `reactivateAccount`, `listSuspensionReasonForUser` | — | out of scope |

Key messages (full definitions in `docs/proto/myteamspeak_common.proto`):

- `LoginData{email=1, password=2, skipSession=3, origin=4 (LoginOrigin:
  CLIENT=0), sync_version=5 (DEFAULT=0, V1_1=1), otp=6, device_id=7,
  otp_renewal_token=8, device_name=9}` — 2FA is a field, not a flow.
- `LoginSession{key=1 bytes, session=2, limits=3, uuid=4, error=5, purge=6,
  addon_dev=7, username=8, myts_id_data=9, mytsid_user_cert=10,
  user_avatar=11, push_token=12, permission=13, user_data=14,
  alternative_login_info=16{renewal_token=1, otp_renewal_token=2,
  device_id=3}}`. Note `key` (bytes) — candidate input to §7.
- `ErrorCommon`: `ERROR_LOGIN_OK=200`, `ERROR_LOGIN_FAILED=202`,
  `ERROR_LOGIN_EMAIL_PENDING=203`, `ERROR_AUTH_TOKEN_INVALID=206`,
  `ERRIR_RENEWAL_TOKEN_INVALID=207` (sic), `ERROR_AUTH_REQUIRES_OTP=208`,
  `ERROR_2FA_OTP_INVALID=209`, `ERROR_SESSION_EXPIRED=103`, …

`UserAccountService` (`/user`) pieces the app may need:
`getBackupKey(UserLogin{email=1, password=2}) → BackupKeyData{returncode=1,
backupkey=2 bytes}` (the recovery-key sidecar), `getAccountData(
AccountDataRequest{session=1, selector=2, client_id=3}) → UserAccountData`
(profile, and `sync_items=25` — a `Sync_Reply_ItemClasses`, so account
data can carry sync items too), 2FA RPCs (`generateOtpSetupSecret`,
`confirmTwoFactorAuthTypeOtp`, …), `setNewUserPublicKey`.

## 3. Local account record (`Account_Serializing.proto`, not on the wire)

What the desktop client persists — a guide to what the app must keep:
`Account_Data{email=1, password=2, uuid=3, user_name=4,
encryption_password=5 bytes, global_items_uuid=10,
class_*_version_uuid=11…20, session=50, limits=51, key=52 bytes,
backup_ed_key=53 bytes, myteamspeakid_data=54, …, push_token=58,
auth_token_cache=62{auth_token=1, renewal_token=2}, otp_renewal_token=64,
device_id=65}`. `Auth_Token_Package{version=1, auth_token=2,
encrypted_encryption_password=3, encryption_tag=4, iv=5}` (all strings —
likely base64/hex; AEAD shape). `TS_Sync_Account{passphrase=1}`.

The 10 `class_*_version_uuid` fields are per-class sync cursors (§4);
`global_items_uuid` pairs with `globalversion`.

## 4. Sync envelope (`synchronization_common.proto`)

`SynchronizationService`: `requestServerItems` and `synchronizeItems`, both
`Sync_Request_ItemClasses → Sync_Reply_ItemClasses`. **CONFIRMED (run6, Q2):**
`requestServerItems` **pulls** — its request carries per-class `version` +
`detail{item_uuid, item_version}` cursors and **no** `item_blob`;
`synchronizeItems` **pushes** — a local change (renamed bookmark) sent its
`detail{item_uuid, item_version, item_blob}` and got back
`status: IN_SYNC` + a fresh `globalversion`. Each push returns a new
`globalversion` (evidence toward Q7: incremental, per-change versioning).

```
Sync_Request_ItemClasses { string session = 1;
                           repeated Sync_ItemClasses_Data classes = 2;
                           string globalversion = 3;
                           Sync_Version sync_version = 4; }
Sync_Reply_ItemClasses   { SyncStatus status = 1;
                           repeated Sync_ItemClasses_Data classes = 2;
                           string globalversion = 3; }
Sync_ItemClasses_Data    { Item_Class itemclass = 1; string version = 2;
                           repeated Sync_ItemClasses_Data_Detail detail = 3;
                           bool not_in_db = 4; }
Sync_ItemClasses_Data_Detail { string item_uuid = 1; string item_version = 2;
                               bytes item_blob = 3;
                               bool item_delte_on_server = 4; /* sic */ }
```

`Item_Class`: `BOOKMARK=0, IDENTITY=1, WHISPER_LIST=2, HOTKEY_PROFILE=3,
ADD_ON=4, CONFIG=5, ITEM_FOLDER=6, GROUP_CHATS=7, CONTACTS=8` (task 1B
closed; `item_room_category` has a version cursor but no class value).
`SyncStatus`: `IN_SYNC=300, NOT_IN_SYNC=301, NOT_IN_DB=302, COLLISION=303,
OVERLIMIT=304`, errors `ERROR_FE_UNKNOWN_METHOD=100,
ERROR_FE_UNKNOWN_DATA=101, ERROR_SESSION_EXPIRED=102, ERROR_CRITICAL=103`.

Flow (CONFIRMED run6, Q2; Q3/Q7 partial): request with session +
`globalversion` + per-class `version` cursors → reply carries changed classes
whose `detail[]` carry `item_uuid/item_version/item_blob`. **`item_blob` is
ENCRYPTED, not a plaintext `Item_Data`** (capture Q4, run6): two pushed blobs
measured 7.57 and 7.41 bits/byte of entropy and do not parse as `Item_Data`.
So §5 describes the **decrypted** shape; the KDF/unwrap (§7, task 1D) sits
between the wire blob and it.

## 5. Item payloads (`Sync_Serializing.proto`, package `com.teamspeak.sync.proto`)

> This is the **decrypted** payload shape. On the wire `item_blob` is
> encrypted (§4/§7, capture Q4) — decode as `Item_Data` only after the §7
> unwrap is reimplemented (task 1D).

Envelope: `Item_Data{item_uuid=2, sync_version_uuid=3, manipulated=4
(ITEM_ADDED=0, CHANGED=1, DELETED=2, NOT_MANIPULATED=3),
last_known_version=5, item_type=6 uint32, parent=7, sort_order=8,
timestamp=9, oneof item_content{bookmark=16, identity=17, whisperlist=18,
hotkeyprofile=19, add_on=20, config=21, item_folder=22, group_chats=24,
contact=25}}`. proto2, so absent vs default is distinguishable.

| Item | Message (field numbers) | App mapping |
|---|---|---|
| bookmark | `Bookmark_Data{name=1, address=2, port=3 uint32, nickname=4, phonetic_nickname=5, identity=6, server_password=7, default_channel=8, default_channel_password=9, default_channel_id=10 uint64, capture_profile=11, playback_profile=12, hotkey_profile=13, autoconnect=14, server_uid=15, server_icon=16, sound_pack=17, show_server_query_clients=18, subscription_mode=19, subscribed_channel_ids=20, channel_passwords=21, send_mytsid_on_server=22 [true], announce_to_chat=23, resolved_server_nickname=24, connect_muted=25}` | `name→name`, `address`+`port→address` (port separate on the wire!), `nickname`, `server_password→password`, `default_channel→channel`; `resolved_server_nickname` dropped like the build plan says (the app fills `serverName` on connect). `server_uid` = stable dedup key (M2). Profiles/hotkeys/sound → drop, document. |
| identity | `Identity_Data{unique_identity=1, id_name=2, nickname=3, phonetic_nickname=4, is_default=5}` | NO auto-import (changes server UID). Gated M5. |
| contact | `Contact{chat_room_id=1, custom_name=2, custom_category=3, notification_preference=4, is_favourite=5, is_direct_chat=6, mytsid=7, chat_member_id=8}` | Greenfield roster (M3). Key on `mytsid`. |
| group chats | `Group_Chats{category_name=1}` | With contacts. |
| folder | `Item_Folder{folder_name=1, folder_type=2 Item_Class}` | `parent` tree; flatten or drop (M3 decision). |
| hotkeys | `HotkeyProfile_data{uuid=1, name=2, hotkeys=3, is_default=4}` | Skip. |
| whisper | `Whisper_list_data{uuid=1, name=2, type=3, …, whisperListEntries=10}` | Skip. |
| addon / config | `Add_on_data{uuid=1, enabled=2}`, `Config_data{default_subscribe_mode=1, user_badges=2, show_user_badges=3, global_presence_token=4, tschat_credentials=5, tschat_de_data=7}` | Skip; `tschat_credentials` is system B material — never touch. |

## 6. System-B boundary (what belongs to chat, not sync)

`…myteamspeak.proto.tschat.*` (20 messages): `AuthenticatedUser{session,
matrix_id}`, `ChatCredentials{domain,username,password}`, `Contact{
ts_chat_identifier, note, matrix_id}`, `ContactList`, `ContactRequest(List)`,
`GroupSession{room_id, shared_session_id, cipher_text}`,
`TschatIdentifierMapping{ts_chat_identifier, matrix_id}`,
`MxidHistory{matrix_id}`, `MoveRequest{new_matrix_id}`, … — all served by
`/tschat` + Matrix homeserver + libolm. The sync `Contact` (§5) carries
**none** of `matrix_id`/`ts_chat_identifier`/devices/keys. Roster ≠ identity.

## 7. Encryption (demonstrated account unwrap and item provider)

**Offline item follow-up:** the account key is directly installed into the
item AES provider; AES-256-CTR with a full-width little-endian counter opens
all eight captured items. A trailing exposed SHA-512 digest of exact plaintext
is checked before protobuf decode. This format is not GCM and is not
authenticated encryption. The [item reference](myteamspeak-bookmark-decryption-protocol.md)
supersedes historical uncertainty below about the tested provider. No new
login or cloud operation was performed.

**Run41 update:** `LoginSession.key` for the tested flow is
`0x02 || tag[16] || nonce[12] || ciphertext[32]`. AES-256-GCM using the
32-byte `ts3Encryption` result and empty AAD authenticates it and yields a
32-byte account key, identical to the desktop output. See the dedicated
[reference](myteamspeak-key-unwrap-protocol.md) for native/server correlation,
synthetic tests and limits. **This is not yet the sync-item decoder.**

**Run40 update (2026-10-14):** two password-based producer derivations are now
demonstrated with native input/output and offline comparisons:

```text
P = UTF-8 password bytes; E = ASCII-lowercased email bytes
login credential = Base64(PBKDF2-HMAC-SHA512(P, E || "ts3Login" || P, 10000, 48))
account encryption value = PBKDF2-HMAC-SHA512(P, E || "ts3Encryption" || P, 10000, 32)
```

Login was validated standalone. The encryption value is a **32-byte raw
producer result**, not proof of the account-key or sync-item unwrap format.
The successful reply's `LoginSession.key` was **61 bytes**, and its wrapping
still needs tracing. See the login reference §8/§10 for evidence and anchors.

**Capture Q4 answered (run6, 2026-09-22): sync item payloads are encrypted.**
Two `synchronizeItems` pushes carried `item_blob`s of 458 B (IDENTITY) and
357 B (CONFIG) at 7.57 / 7.41 bits/byte of entropy that do not parse as
`Item_Data`. So opaque blobs, not cleartext protobuf → the KDF/unwrap must be
reimplemented before any item read/write in the app (M2+). The plaintext
`Item_Data` (§5) is what the client sees *after* decrypting in-process.

Historical pre-run40 findings: `Auth_Token_Package{…, encrypted_encryption_password,
encryption_tag, iv}`, `!salt.empty()` assert, `decrypted_user_private_key`,
`AEAD_AES_{128,256}_GCM` markers, `Encryption_Impl` + `Encryption_Impl_V2`,
vendored `teamcrypto/.../libtomcrypt`, assert
`"plain_hash.size() == teamcrypto::sha2::sha512_size"`. Static negative
(2026-09-09): `pbkdf|hkdf` 0 hits, `scrypt|argon` only vendored OpenSSL
provider paths — no app-level KDF call found. Working hypothesis: per-item
encrypted blobs with a recovery-key-derived key; `Auth_Token_Package` wraps
the encryption password. **Those string-grep negatives did not rule out
PBKDF2:** run40 subsequently identified and demonstrated the actual producer
calls described above.
Key material with known field numbers (2026-09-22, from `docs/proto/`):
server → client `LoginSession.key=1` (bytes), `BackupKeyData.backupkey=2`
(bytes, via `getBackupKey(UserLogin{email, password})`), `UserData.key=3` /
`backupkey=4` (bytes, `user` package); stored locally as
`Account_Data.encryption_password=5`, `key=52`, `backup_ed_key=53`;
`MyTeamSpeakIdData.user_private_key{encrypted_user_private_key=1}`. The
account-key unwrap / derivation from these to the item key is still unknown —
next step is decompiling `Encryption_Impl_V2` / `Item_Manager` (the
`!salt.empty()` assert), not more string grepping.
Capture decided (run6): opaque blobs, so **KDF reversing is the critical
path** before any M2+ build. A good dynamic follow-up is to break where the
blob is decrypted (feed the captured `item_blob` back in) rather than static
decompilation alone — the same in-process gdb approach that read the RPC
bodies can read the plaintext `Item_Data` and the key/iv at the crypto call.

## 8. Change log

- 2026-10-14 (offline run41b item follow-up): independently decrypted five
  bookmarks, two identities and one config item using the unwrapped account
  key, with exact native/plaintext/digest and server-blob correlation. Added
  synthetic tests and a sans-IO Rust item primitive in `../ts6-lib/crates/tslib-myts`.
  26 Python and 26 Rust tests pass. Documented the exposed unkeyed-digest
  authenticity limitation. No network/login/session/cloud mutation.

- 2026-10-14 (run41): version-2 account-key unwrap demonstrated with one
  authorized isolated desktop login through the owner's tunnel gateway and
  an independent authenticated AES-256-GCM comparison. Added offline
  reference/goldens; 15 login/unwrap tests pass. The research session was
  explicitly deleted (204). Item-key derivation/framing/integrity and token
  renewal remain open; no application source changes.

- 2026-10-14 (run40): login KDF demonstrated, standalone password login
  returned HTTP 200 / protobuf `ERROR_LOGIN_OK=200`, its own session deletion
  returned 204, and the distinct 32-byte `ts3Encryption` producer derivation
  matched native output. Added the durable login reference; sync unwrap and
  renewal remain open. Implementation target is Flutter, not legacy Kotlin.

- 2026-09-09: initial static snapshot (endpoints, message/field names). Tag
  numbers, RPC method names (beyond `requestServerItems`), enum values, KDF,
  and all byte-level framing await Phase 2.
- 2026-09-09 (evening): Phase-1 completion pass — provenance pinned
  (`TeamSpeak` 66365272 md5 `8234f961…`, tschat-lib 20326736 md5
  `c80d95c7…`, `main.js` 10080350 md5 `ab4fd33a…`); second sync verb
  `synchronizeItems` + auth stubs `login/loginWithAuthToken/
  loginWithRenewalToken/session/getBackupKey/getKey` inventoried (wire
  mapping TBD); `pbkdf|hkdf` negative, `Encryption_Impl_V2` +
  `teamcrypto/libtomcrypt` noted; `BackupKeyData`,
  `MyTSID_Verification_Token`/`verify_tschat_mytsid_token` added as TBD;
  Go-lib exclusion re-confirmed (0 hits).
- 2026-09-22: **descriptors recovered.** The binary embeds all 23
  TeamSpeak `FileDescriptorProto`s; `docs/proto/extract_descriptors.py`
  extracts them and verifies a byte-identical protoc round trip. Tasks 1A
  (field numbers/types), 1B (`Item_Class` values) and 1C (RPC table with
  service mapping) closed. Earlier guesses corrected: `getKey` is an admin
  `UserManagementService` RPC; `LoginData` also has `skipSession`,
  `origin`, `sync_version`; bookmarks carry `port` separately; `item_blob`
  is `bytes`. Request framing disassembled from `teamprotobufrpc`
  (`u8 len + method name + protobuf`), response is bare protobuf on
  HTTP 200 — STATIC until the first live call. KDF (task 1D) still open.
- 2026-09-22 (run6): **first live capture.** In-process gdb
  (`tools/myts/gdb_capture.py`) read RPC bodies as plaintext inside the
  isolated client, before TLS. Confirmed: request framing
  `u8 len + method + protobuf` and bare-protobuf reply on the wire; body arg
  is `rcx` (not `rdx`) at the `0x1dfd82a` POST call. Captured real
  service→method mapping for `/authentication`, `/synchronization`, `/user`,
  `/integration`, `/tschat` (§0). **Q2 answered** (`requestServerItems` pulls,
  `synchronizeItems` pushes). **Q4 answered: item payloads are encrypted**
  (entropy ~7.5 bits/B, no `Item_Data` parse) → KDF (1D) is the critical path.
  Q1 partial (session-based auth only; the profile was already logged in, so
  the full `login` flow was not exercised); Q3 partial (pull-reply item blobs
  were mis-correlated during the startup burst — see the tool's known limit).
