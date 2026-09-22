# myTeamSpeak — sync protocol reference (system A)

> **Status:** Phase-1 static snapshot (2026-09-09, client build 2025-07-13).
> This document supersedes `myteamspeak-overview.md` /
> `myteamspeak-research-plan.md` on wire details once Phase-2 capture lands.
> Conventions: tables give **names in field order** as seen in descriptor
> blobs; tag numbers/types are **TBD (Phase 2, task 1A)** unless stated.
> Anything marked TBD/HYPOTHESIS is not yet wire-verified.

## 0. Transport (verified: endpoints + framing strings; TBD: bytes)

- Base `https://clientapi.myteamspeak.com`, path-per-service (§1).
- Sync RPC: `POST /synchronization`, `Content-Type: application/ts3cloud`,
  `User-Agent: cpp-httplib/0.11.1` (forum captures), ProtobufRPC framing
  (`ProtobufRPC`, `ProtobufItems`, `SQLite TABLE ProtobufItems` strings in
  binary). Named sync RPC stubs: **`requestServerItems` AND
  `synchronizeItems`** (both present as `Method …() not implemented.`; which
  one goes on the wire is TBD — capture Q2). Auth/session stubs:
  `login()`, `loginWithAuthToken()`, `loginWithRenewalToken()`,
  `session()`, `getBackupKey()`, `getKey()` (service mapping TBD — Q1).
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

## 2. Auth / session messages (`com.teamspeak.myteamspeak.proto`, top-level)

No `authentication.*` / `session.*` sub-package exists (verified negative).
All auth/session messages are top-level:

| Message | Fields (blob order) | Notes |
|---|---|---|
| `LoginData` | `email, password, otp, device_id, otp_renewal_token, device_name` | OTP present → 2FA login is a field, not a separate flow |
| `LoginSession` | `session, uuid, username, push_token` + `AlternativeLoginInformation{renewal_token, otp_renewal_token, device_id}` | |
| `LoginStatus` | `uuid` | |
| `AuthTokenRequest` | `email, password` | |
| `AuthToken` | `id, mytsid` | |
| `AuthTokenLogin` | `auth_token, device_description` | |
| `AuthTokenReply` | `auth_token` | |
| `RenewalToken` | `token` | |
| `RenewalTokenLogin` | `renewal_token, auth_token` | Renewal path (capture Q6) |
| `Session` | `session` | Bare session wrapper |
| `MyTeamSpeakIdData` (+ `UserPrivateKey`) | TBD | myTSID cert material |
| `MyTSUserCertificate` | TBD | |
| `UserData` | `description` | |
| `Permissions` | `permission` | |
| `BackupKeyData` | TBD (fields) | `Closure<UserLogin,BackupKeyData>`, `m_request_backup_ed_key_binder`; UI `BackupKey`/44-char check — recovery-key sidecar |
| `MyTSID_Verification_Token` | TBD | Seen as `account.proto` descriptor + `verify_tschat_mytsid_token`; details TBD |

Related: `user.AuthenticatedDevice{device_id, device_name, region}`,
`user.UserAccountData{username, email_address, ts_chat_id, description,
author_name, phone}`, `login.*` (`AuthTokenExpireRequest{email,password,id}`,
`AuthTokenListRequest{email,password}`, `…Reply.Entry{device_description,id}`,
`requestExpireTime{uuid}`, `AccountStatus{Info{email,reason},Reply{error_msg}}`).
2FA: `user.TwoFactorAuthType{Request{session},Response,
OtpConfirmationRequest{session,otp}}`, `UpdateTwoFactorAuthTypeRequest{session}`,
`OtpSecretResponse{otp_secret, otp_qr_code_mime_type}`,
errors `ERROR_2FA_{DEVICE_ID_MISSING,OTP_INVALID,OTP_SECRET_MISSING}`,
`ERROR_AUTH_REQUIRES_OTP`.

## 3. Local account record (`com.teamspeak.account.proto`)

| Message | Fields |
|---|---|
| `Account_Data` | `email, password, uuid, user_name, global_items_uuid,` `class_bookmark_version_uuid, class_identity_version_uuid, class_add_on_version_uuid, class_config_version_uuid, class_hotkey_profile_version_uuid, class_whisper_list_version_uuid, class_item_folder_version_uuid, class_item_room_category_version_uuid, class_group_chats_version_uuid, class_contact_version_uuid,` `push_token, firebase_device_token, otp_renewal_token, device_id` |
| `Account_Data.AuthTokenCache` | `auth_token, renewal_token` |
| `Account_Data.IntegrationCache` | `user_integration_id` |
| `Account_Session` | `id` |
| `Auth_Token_Package` | `auth_token, encrypted_encryption_password, encryption_tag, iv` (AEAD shape) |
| `TS_Sync_Account` | `passphrase` (recovery-key derived — task 1D) |

The 10 `class_*_version_uuid` fields are the per-class sync cursors (§5).

## 4. Sync envelope (`synchronization.*`)

| Message | Fields |
|---|---|
| `Sync_Request_ItemClasses` | `session, globalversion` |
| `Sync_ItemClasses_Data` | `version` (+ per-item details) |
| `Sync_ItemClasses_Data_Detail` | `item_uuid, item_version` |
| `Sync_Reply_ItemClasses` | `globalversion` (+ item payloads) |
| `Item_Class` | enum, values TBD (ints on the wire; task 1B) |
| `Sync_Version`, `SyncStatus` | TBD |

Flow (HYPOTHESIS, confirm in capture Q2/Q3/Q7): request with session +
`globalversion` cursor → reply with new `globalversion` + changed classes →
per-item detail exchange keyed by `{item_uuid, item_version}`.

## 5. Item payloads (`com.teamspeak.sync.proto.*`)

Envelope for every item: `Item_Data{item_uuid, sync_version_uuid,
last_known_version, parent, sort_order}` + `Item_Data.Manipulation_Flag`.
`parent`/`sort_order` carry the folder tree; folder nodes are `Item_Folder`
(see below). Enum `Item_Type` travels as int (`unknown` = 0 asserted
against); int→class map is TBD (task 1B — request one class at a time).

| Item class | Message | Fields (blob order) | App mapping |
|---|---|---|---|
| bookmark | `Bookmark_Data` | `name, address, nickname, phonetic_nickname, identity, server_password, default_channel, default_channel_password, capture_profile, playback_profile, hotkey_profile, server_uid, server_icon, sound_pack, resolved_server_nickname` (+ `ChannelPassword{password}`, `SubscriptionMode`) | `name→ServerBookmark.name`, `address→address`, `nickname→nickname`, `server_password→password`, `default_channel→channel`. Profiles/hotkeys/sound have no app equivalent → drop on import, document. `server_uid` useful as stable dedup key alongside `address`. |
| identity | `Identity_Data` | `unique_identity, id_name, nickname, phonetic_nickname` | NO auto-import (would change server UID). Park for gated M5. |
| contact (legacy roster) | `Contact` | `chat_room_id, custom_name, custom_category, mytsid, chat_member_id` (+ `NotificationPreference`) | Greenfield local roster (no store exists). Key on `mytsid`; display `custom_name` else myTS name from `user.*`. |
| group chats (legacy) | `Group_Chats` | `category_name` | With contacts (same version uuid family). Details TBD. |
| folder | `Item_Folder` | `folder_name` | Map onto `parent` tree; app list is flat → flatten with `Folder/Name` label or drop folders on import (decision M3). |
| hotkeys | `HotkeyProfile_data{uuid, name}` + `Hotkey{event_uuid, event_mode, action_uuid, action_mode, action_flag, action_description, action_plugin, action_away_message, action_soundpack, action_plugincommand, action_plugindescription, action_deviceuid, action_devicename, action_target, action_profiles}` + `KeyDef{identifier, key}` + `OS` | — | Skip (no equivalent). |
| whisper | `Whisper_list_data{uuid, name, targetGroupName, targetServerUid, targetServerName}` + `WhisperEntry{name, uid}` + `WhisperEntryType` + `WhisperListType` | — | Skip. |
| addon/config | `Add_on_data{uuid}`, `Config_data{user_badges}` | — | Skip. |
| chat creds | `Chat_Credentials{domain, username, password}` | System B material — do not touch in sync milestones. |
| legacy chat ref | `TSCHAT_DE_Data{url, identity, username, server_id, address, port, name}` | Legacy pointer — document only. |

## 6. System-B boundary (what belongs to chat, not sync)

`…myteamspeak.proto.tschat.*` (20 messages): `AuthenticatedUser{session,
matrix_id}`, `ChatCredentials{domain,username,password}`, `Contact{
ts_chat_identifier, note, matrix_id}`, `ContactList`, `ContactRequest(List)`,
`GroupSession{room_id, shared_session_id, cipher_text}`,
`TschatIdentifierMapping{ts_chat_identifier, matrix_id}`,
`MxidHistory{matrix_id}`, `MoveRequest{new_matrix_id}`, … — all served by
`/tschat` + Matrix homeserver + libolm. The sync `Contact` (§5) carries
**none** of `matrix_id`/`ts_chat_identifier`/devices/keys. Roster ≠ identity.

## 7. Encryption (TBD — task 1D + capture Q4)

Known shape only: `Auth_Token_Package{…, encrypted_encryption_password,
encryption_tag, iv}`, `!salt.empty()` assert, `decrypted_user_private_key`,
`AEAD_AES_{128,256}_GCM` markers, `Encryption_Impl` + `Encryption_Impl_V2`,
vendored `teamcrypto/.../libtomcrypt`, assert
`"plain_hash.size() == teamcrypto::sha2::sha512_size"`. Static negative
(2026-09-09): `pbkdf|hkdf` 0 hits, `scrypt|argon` only vendored OpenSSL
provider paths — no app-level KDF call found. Working hypothesis: per-item
encrypted blobs with a recovery-key-derived key; `Auth_Token_Package` wraps
the encryption password. **No KDF identified yet** (`pbkdf|scrypt|argon|hkdf`
grep done — negative).
Capture decides: cleartext protobuf in `Sync_Reply` → schema task only;
opaque blobs → KDF reversing becomes the critical path before any M2+ build.

## 8. Change log

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
