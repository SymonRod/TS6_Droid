# docs/proto

> **Current-build login update (2026-10-14):** these committed files are still
> the older verified schema snapshot below. Run39 extracted newer descriptors
> (MD5 `7eb9fdb8…`) into ignored captures, but they have not been rendered and
> round-trip verified here. Current login fields, recovery additions/errors,
> demonstrated KDF and successful standalone decoding are documented in
> **[../myteamspeak-login-protocol.md](../myteamspeak-login-protocol.md)**.
> Do not overwrite generated schemas by hand or treat the old file's missing
> recovery fields as evidence that the current server lacks them.

myTeamSpeak `.proto` files **recovered, not reconstructed**: the desktop client
links full protobuf reflection, so each generated file embeds its serialized
`FileDescriptorProto`. `extract_descriptors.py` pulls them out of the binary,
renders them as source, and checks that `protoc` compiles every file back to
the identical descriptor (field numbers, types, labels, defaults, oneofs,
reserved ranges, services). Nothing here is guessed.

Source: `/opt/teamspeak/TeamSpeak`, desktop client 2025-07-13, 66365272 B,
md5 `8234f961015da34f1387fa735a7443b0`; protobuf runtime 32.0 (conan path in
the binary). 23 TeamSpeak descriptors exist; only the import closure of the
five files below is committed (12 files). Re-run with `--all` into a scratch
directory for the rest (management, push, addon, revocation, blacklist, …).

```bash
python3 docs/proto/extract_descriptors.py            # rewrite + verify in place
python3 docs/proto/extract_descriptors.py BIN OUT --all
```

| File | What it gives the app |
|---|---|
| `myteamspeak_login.proto` | `LoginService`: `login`, `requestAuthToken`, `loginWithAuthToken`, `loginWithRenewalToken`, `session`, `deleteSession`, … |
| `myteamspeak_common.proto` | `LoginData`, `LoginSession`, `AuthToken*`, `RenewalTokenLogin`, `ErrorCommon` |
| `myteamspeak_synchronization.proto` | `SynchronizationService`: `requestServerItems`, `synchronizeItems` |
| `synchronization_common.proto` | `Sync_Request/Reply_ItemClasses`, `Item_Class` / `SyncStatus` values |
| `Sync_Serializing.proto` | Item payloads: `Item_Data` oneof → `Bookmark_Data`, `Contact`, … |
| `Account_Serializing.proto` | The client's local account record (`Account_Data`, `Auth_Token_Package`) — not on the wire, shows what it keeps |
| `myteamspeak_user.proto` | `UserAccountService` (`getBackupKey`, `getAccountData`, 2FA, …) |

The rest are imports. The golden `protoc --decode_raw` test from M0 now has
captured payloads: `captures/myts/run6-*.req.bin` (framed `u8 len + method +
protobuf`) decode cleanly with these schemas via `tools/myts/analyze.py`.
Note (run6): sync `item_blob`s on the wire are **encrypted**, so a
`Sync_Reply` reply does not decode to a plaintext `Item_Data` until the KDF
(task 1D) is reimplemented — use a request payload for the golden test.
