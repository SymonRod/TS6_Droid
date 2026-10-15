# Account chat and automatic encrypted-history restoration

**Research follow-up: 2026-10-15. Target: Flutter, not the legacy Kotlin app.**

**Second follow-up, same day:** clarified the export discriminators using Go
struct metadata, exercised valid synthetic Megolm keys/messages with the bundled
libolm, and performed an explicitly authorized demo-account read probe. See
§5.1, §7.1 and §9 for the new evidence and its limits.

**Latest compatibility correction (2026-10-15), §16:** a missing numeric
`chain_index` in the research `m.room_key` payload prevented official desktop
receipt. After a compatible key share at the existing ratchet index 3, the owner
confirmed desktop display of messages **3/4/5**. An independently returned
recipient cloud **type-2** backup decrypted all three with exact plaintext
comparison and matching sender/Curve25519/claimed Ed25519 metadata, without the
own-type-1 exception. Actual first-known index is **3 despite JSON
`chain_index=0`**; original messages 0/1/2 are not recovered. No reset, new device,
session rotation or research cloud upload occurred in the correction. See §16
for the cause, partial-history limit, retained state and next gates.

**Earlier two-account follow-up (2026-10-15), superseded by §16:** the owner supplied two disposable
accounts and authorized autonomous messaging tests. **Three encrypted dummy
events were sent from account 2 and fetched by account 1**, with indices 0/1/2
in one session. This includes local exact-plaintext checks, not recipient cloud
decryption. Four exact-pair recipient cloud queries returned success but zero
entries; incoming cloud metadata/decryption remain unverified. One identifiable
research device was added only to account 2; account 1 reused its existing
record. Device-key publication and Olm room-key sharing were authorized in this
follow-up. No cloud backup was uploaded by the research. See §15 before resuming.

**Earlier authorized resumption (2026-10-15):** the owner made revocation
of the earlier unidentified research device optional and explicitly authorized
the bounded follow-up. **The empty sync is now explained by its filters:**
changing only timeline types from `m.room.encrypted` to `m.room.message` reveals
one joined room and three plaintext message events. Broader/unfiltered sync,
joined-room listing, direct-room data and bounded scrollback agree. **One real
encrypted event has now been recovered and decrypted through a targeted cloud-key
pull (§14)**, after the owner enabled encryption and sent a dummy message. The
backup was type 1 with empty sender/device-identity strings; the research helper
now handles that narrowly for an own-account outbound event without claiming
verified device identity. One additional research device was created in §12;
its token/ID are retained in an owner-only ignored record and were reused, not
lost. No additional Matrix login was needed for §13–14. The older device's
revocation remains unconfirmed. Read §12–14 for the evidence and safety decisions;
§10–11 preserve the earlier stop state. Do not rerun the old probe blindly.

This extends [the contacts/chat reference](myteamspeak-contacts-chat-protocol.md)
without changing the parallel contacts/avatar implementation. It describes the
official desktop's protocol, not an implemented or live-verified Droid chat.

## 1. Main result and evidence boundaries

The desktop has an automatic **myTeamSpeak cloud backup/recovery path for
Megolm room-session keys**. It does not need to ask for a second chat-history
password: that path uses the account encryption provider already unlocked by
myTeamSpeak sign-in. There is also a local persistent crypto cache.

The previously open **outer cloud-session envelope** is now resolved for the
pinned version-2 desktop provider:

```text
P = UTF-8 JSON describing a chat group session
cipher_text = standard_Base64(
    IV16 || AES-256-CTR-128LE(raw_account_key, IV16, P) || SHA512(P)
)
```

It is the same inner cipher/digest framing as a sync item, with an additional
Base64 text layer. It is **not** the version-2 GCM account-key envelope and is
**not** standard Matrix key-backup/secret-storage framing. The SHA-512 suffix
is unkeyed: a successful digest check is not proof of authenticity or sender
trust.

| Claim | Evidence obtained in this follow-up | Limit |
|---|---|---|
| Cloud wrapper uses the unlocked account provider | Static C++ call chain and raw-key setter; **LIVE §14:** the unlocked raw account key decoded a real selected cloud-session envelope and its receive key decrypted an event | One own-account type-1 backup; not all provider versions or backup completeness |
| Exact outer envelope | **Independent offline desktop oracle:** 3 generated plaintexts, both encryption/decryption directions; 5 native rejection cases | Fabricated JSON uses placeholder Megolm material; this does not test session import or historical-message decryption |
| Missing-key recovery path | Static Go `decryptEvent` → cloud-key request; **LIVE §14:** real encrypted event → exact room/session cloud read → unwrap → fresh inbound libolm session → successful decryption | Research Python orchestrator, not production automatic recovery; one own type-1 event, no complete history or verified device identity |
| Matrix login, rooms and history | **LIVE:** corrected-header login and broader sync show one direct room; ordinary scrollback works (§12), then one encrypted event after owner activation/send is retrieved and decrypted (§14) | No JWT, device-key upload or research message send; no full history or Flutter chat implementation |
| Service availability | **LIVE controlled comparison:** standard Python/curl request 503; `Go-http-client/1.1` 200 on same login endpoint; gateway also 200 | Actual routing/filter mechanism and complete acceptable-UA set unknown; not a demonstrated global outage |
| Desktop shows old messages without another password | Owner's observation | Does not distinguish local cached plaintext/keys from a fresh cloud restoration |
| Meaning of export types 1/2/3 | **STATIC:** named `GroupSession` fields, exporter branches/constants and resolved interface methods | No native Go exporter/importer invocation with valid sessions |
| Valid keys and partial history | **OFFLINE, bundled libolm:** sharing/export formats, synthetic envelope → receive session → message decryption, nonzero index, replay and tampering tests | JSON dispatch is reconstructed Python, not the desktop Go JSON importer or an independent Megolm implementation |
| Cloud-session read RPC | **LIVE:** empty-selector success/zero entries (§9); exact-pair request returns one real type-1 backup and permits decryption (§14) | Empty-selector enumeration semantics and backup completeness remain unknown; no backup writes |

The initial offline investigation needed no real credentials, tokens, message
contents, session keys or new captures. The second follow-up used `.env` account
credentials and a temporary myTeamSpeak session in memory only; no real messages
or Megolm keys were obtained or logged. Existing desktop/app profiles were not
opened, cleared or altered.
The later header-corrected probe also used generated chat credentials and a new
Matrix access token in memory; see §10–11 for its results and incomplete cleanup.
The later §14 experiment obtained a real receive key and decrypted an event in
memory only; the earlier "no real keys/messages obtained" statements describe
their respective earlier stages, not the current aggregate evidence.

## 2. Keep the three authentication/key layers separate

```text
myTeamSpeak password sign-in
  ├─ session token → authenticated /tschat control-plane RPCs
  ├─ encryption KDF → GCM unwrap → raw account key
  │    └─ cloud cipher_text decode → chat-session JSON → Megolm receive session
  └─ decrypted CONFIG.chat credentials
       └─ Matrix /login → Matrix access_token + device_id + user_id
            └─ /sync, rooms, encrypted timeline events
```

The myTeamSpeak password, generated chat password, account key, Matrix access
token, Olm device keys and Megolm room-session keys are different objects.
Do not use a myTeamSpeak bearer/session token as a Matrix access token, or pass
the user's myTeamSpeak password to a guessed Matrix host.

The raw account key is installed directly into the version-2 item provider by
`0x2a830e0`; that relationship was independently established in the
[bookmark cipher investigation](myteamspeak-bookmark-decryption-protocol.md).
This follow-up traces the cloud-chat code back to that same provider.

### Why the desktop can show old messages automatically

There are at least two supported explanations, which can coexist:

1. Its persistent store already contains messages and/or the necessary receive
   sessions. The desktop can reuse them without another prompt.
2. When an encrypted event references a missing session, the client can ask
   myTeamSpeak for the backed-up session, unwrap it with the unlocked account
   provider, import it and retry stored messages. Matrix device-to-device key
   requests are another path in the client.

Seeing messages on an existing desktop is therefore **not** evidence that an
uninitialized phone can fetch every historical key, or that the currently failing
public Matrix endpoint is healthy. Do not reset either client's keys or remove
its cache to distinguish these cases. A disposable synthetic/offline test or a
separately authorized fresh-profile test is required.

## 3. Matrix transport and bootstrap reconstructed from desktop

The bundled chat library is Go (`go1.21.0`, `tschat_client_lib`) with libolm.
Its normal data transport is HTTPS requests with JSON and
`Authorization: Bearer <Matrix access token>`. Updates arrive through HTTP
long-poll `/sync`; this is not the TeamSpeak command socket or a proprietary
chat WebSocket.

The inspected native `MatrixClient.login` calls `CheckLogins`, which performs:

```text
GET <base>/_matrix/client/r0/login
```

An important build-specific detail: **`CheckLogins` explicitly requires a flow
named `m.login.password`**, even though the credential parser and `Login` also
contain `org.matrix.login.jwt` support. The presence of the JWT branch alone
does not establish an operational JWT bootstrap. Do not synthesize a JWT or
substitute standard `m.login.token` for this extension.

The password request reconstructed from the native JSON structs is:

```json
{
  "type": "m.login.password",
  "identifier": {"type": "m.id.user", "user": "<chat username>"},
  "password": "<generated chat password>"
}
```

It is POSTed to `.../r0/login`. The inspected `loginRequest` has exactly
`identifier`, `password`, `token`, and `type`: **this build does not send a
`device_id` or `initial_device_display_name` in that request**. Matrix then
assigns a device ID. Native `LoginData` decodes `user_id`, `access_token`,
`home_server`, and `device_id`. Reuse of stored login data is separate from
generating a new device on every login.

The static connect sequence is:

1. Reuse stored login data when available; otherwise discover flows and login.
2. Upload device/one-time keys.
3. Run initial `/sync`, process the initial data and initialize room state.
4. Start ongoing sync/key maintenance and retrying stored encrypted messages.

This is also why calling the desktop's complete connect routine is **not a
read-only reachability probe**: after login it uploads keys and can update
profile/avatar/contact state. None of those operations was invoked live here.

### Principal endpoint map

These routes are reconstructed from function bodies, not just free-standing
binary strings. `<base>` is the selected account/server endpoint, not a host
to hardcode. Path IDs and query values need proper encoding.

| Action | Desktop route/method |
|---|---|
| Flow discovery / authenticate | GET / POST `/_matrix/client/r0/login` |
| Incremental state/timeline | GET `/_matrix/client/r0/sync`, `since`, `timeout`, `filter`, `set_presence` |
| Device and one-time keys | POST `.../r0/keys/upload`, `.../r0/keys/query`, `.../r0/keys/claim` |
| To-device Olm/key traffic | PUT `.../r0/sendToDevice/<event-type>/<transaction-id>` |
| Create room | POST `.../r0/createRoom` |
| Timeline send | PUT `.../r0/rooms/<room>/send/<event-type>/<transaction-id>` |
| Older messages | GET `.../r0/rooms/<room>/messages`, direction/limit/filter/pagination token |
| A single event | GET `.../r0/rooms/<room>/event/<event>` |
| Members | GET `.../v3/rooms/<room>/members` |
| Event context | GET `.../v3/rooms/<room>/context/<event>?limit=...` |
| Presence | PUT `.../r0/presence/<user>/status` |

Direct-room and ignored-user mappings use account data (`m.direct`,
`m.ignored_user_list`); they are distinct from the myTeamSpeak contact roster.
Room membership, timeline cursors, to-device events and device-list updates
must survive incremental sync. Persist an accepted `next_batch` consistently
with the events/keys processed before advancing the cursor. Do not replace a
local timeline with an empty list after a 503.

The desktop uses a mixture of `r0`, `v3` and `v1` routes. That is not evidence
that choosing `v3/login` will bypass the observed server-side 503.

## 4. Message encryption versus cloud-session wrapping

For room events the native sender builds the standard Megolm payload:

```json
{
  "type": "m.room.encrypted",
  "content": {
    "algorithm": "m.megolm.v1.aes-sha2",
    "sender_key": "<sender Curve25519 key>",
    "device_id": "<sender device>",
    "session_id": "<Megolm session>",
    "ciphertext": "<Megolm message>"
  }
}
```

The encrypted plaintext includes the inner event `type`, `content` and
`room_id`. libolm handles the ratchet/message crypto. Device-to-device
communication uses `m.olm.v1.curve25519-aes-sha2`, including `m.room_key` and
`m.forwarded_room_key`. `m.room_key_request`/cancellation are separate operations.

Receiving a cloud session is **not decrypting the timeline itself with the
account key**. The account key unwraps a backup that contains Megolm session
material; that material then decrypts the room's ciphertext.

Preserve and validate room/session/sender associations, claimed signing keys,
forwarding information and replay-index bookkeeping. An imported cloud key is
not automatically a verified Matrix device. Never claim authenticated origin
just because the outer SHA-512 suffix matches. An imported ratchet might cover
only messages from a particular index onward.

## 5. Cloud session RPC and plaintext format

The existing `/tschat` protobuf schema contains:

```text
getGroupSessionData(GroupSessionRequest) -> GroupSessionResponse
GroupSessionRequest { user = 1; repeated group_sessions = 2; }
AuthenticatedUser { session = 1; matrix_id = 2; }
GroupSession { room_id = 1; shared_session_id = 2; cipher_text = 3; }
GroupSessionResponse { error = 1; repeated group_sessions = 2; }
```

Transport is the existing `application/ts3cloud` method-prefix framing at
`https://clientapi.myteamspeak.com/tschat`, **not** a Matrix endpoint. Treat the
room/session IDs as opaque pairs and match returned entries to requests. A
future read-only probe must bound counts, sizes, time and decompressed bytes
and check application errors independently of HTTP status.

The Go export constructs JSON with these fields:

| Field | Native representation / significance |
|---|---|
| `version` | **String `"1"`**, not numeric 1 |
| `room_id` | String; importer compares with the requested room |
| `group_session_id` | String; importer compares with the requested session |
| `algorithm` | String; importer requires `m.megolm.v1.aes-sha2` |
| `type` | Numeric discriminator 1, 2 or 3 |
| `group_session_key` | Secret session material string |
| `chain_index` | Numeric ratchet position |
| `sender` | Sender user ID string |
| `c25519` | Sender Curve25519 key string |
| `ed25519` | Claimed signing key string |

**Live correction (§14):** an own-account type-1 backup contained explicit empty
strings for all three identity fields. They are not universally nonempty, and
missing metadata must not be manufactured or described as a verified sender.

Type 3 export additionally includes `sender_claimed_ed25519_key`,
`forwarding_curve25519_key_chain`, and `sender_key` in the inspected exporter.
Do not assume that those fields replace the common `c25519`/`ed25519` fields.
The cloud importer validates/reads the common fields above; full forwarded-key
trust reconciliation remains an implementation gate.

**The discriminator changes libolm's initialization mode:**

- Types 1/2 reach `olm_init_inbound_group_session` (session-sharing key format).
- Type 3 reaches `olm_import_inbound_group_session` (exported receive-session
  format, distinct from the sharing key format).

This follows the actual Go call targets, despite potentially misleading helper
names (`newImportedInboundGroupSession` calls **init**, while the separate
`InboundGroupSession.Import` calls **import**). Do not treat these formats as
interchangeable or feed every key through a generic JSON key-backup importer.

### 5.1 Export discriminator semantics and index boundaries

Go's native struct metadata identifies `crypto.GroupSession` at `0xdafe80` in
the pinned Go ELF. Relevant field offsets are `OutSession=0x0`,
`InSession=0x10`, `EarliestKey=0x50` (byte slice), `CtrIndex=0x80`,
`Exported=0x90` (string), and `IsExportedToMyTSCloud=0xd0` (bool).
`Exported` is key material, **not** the boolean backup-completion flag.

The exporter at `0x56c3e0` selects these branches:

| Type | Static selection and exported material | JSON `chain_index` |
|---:|---|---|
| 1 | Nonempty `EarliestKey` and an `OutSession`; exports that earliest sharing key, and obtains the session ID from the outbound session | Literal 0 |
| 2 | Nonempty `EarliestKey`, no outbound session and an `InSession`; exports the earliest sharing key, with the inbound session ID | Literal 0 |
| 3 | Empty `EarliestKey`; exports the stored `Exported` string and obtains the inbound session ID | Stored `CtrIndex` |

The type constants at `0xc38170`, `0xc381b0`, `0xc381c8` are respectively
1, 2, 3. The first two types **do not represent different libolm key formats**.
They distinguish the exporter's session state. The importer merges both into
the same receive-only creation path; even a type-1 backup does not restore the
old outbound ratchet/signing private key or revive the old sending device.
`CreateGroupSessionFromSharedData` initializes only `InSession` in both modes.

Interface-table resolution corroborates this: outbound table `0xdda690`
has `SessionID` at `+0x40` → `0x51cec0`; inbound table `0xddad98` has
`SessionID` at `+0x48` → `0x51de40`. The type-3 exporter reads the stored
`Exported` field; that branch does **not** itself call libolm's `Export`.
Do not equate type 3 with a verified forwarding chain or assume all of its
extra fields have been reconciled by the cloud importer.

**`chain_index=0` alone does not prove full history coverage.** A sharing key
can itself start at a nonzero ratchet index. The synthetic libolm test shared
a key after message 0: it could decrypt message 1 but rejected message 0 with
`UNKNOWN_MESSAGE_INDEX`. An exported receive key starting at 2 similarly
decrypted messages 2/3, not 0/1. Obtain the actual first-known index from the
initialized session, reconcile metadata deliberately, and never claim recovery
of older ciphertext merely because the JSON's index is zero.

All forwarded-key trust rules and real-account backup completeness remain open.
There was no cloud upload, Matrix device-key request, reset, clear-session
operation or real-history decryption in either follow-up. The second follow-up
did execute a read-only cloud-session RPC, as detailed in §9.

## 6. Recovered C++ wrapper call chain

All addresses below are ELF virtual addresses in the **pinned** supplied
`../teamspeak/TeamSpeak`, not process addresses and not offsets for another
release. Add the process load base only when debugging that exact ELF.

| Location | Observation |
|---|---|
| Upload call `0x2a972df` | Cloud service invokes sync-interface vtable `+0x108` on the session JSON payload |
| Receive call `0x2aa55da` | Cloud service invokes sync-interface vtable `+0x110` on protobuf `cipher_text` |
| Sync vtable `0x4a76920` | Slots resolve to `0x2a5a820` / `0x2a5a860` |
| `0x2a5a820` → `0x2a80700` | Existing unlocked encryption object → binary item encryption → Base64 |
| `0x2a5a860` → `0x2a80780` | Base64 decode → `0x2a80410`, the demonstrated item decrypt/digest verifier |
| `0x2a80700` → `0x2a7ffa0` | SHA-512 of plaintext, provider encryption, digest suffix append |
| `0x2a81970` / `0x2a81990` | Text encode/decode adapters; native oracle confirms standard Base64 |
| Provider `0x4a77d98`, key setter `0x2a830e0` | Version-2 raw account key, same provider as sync items |

The trace resolves what was left open in section 7 of the earlier reference;
it does not generalize this framing to unknown provider versions.

The Go library, `../teamspeak/libtschat_client_lib_export.so` (not the small
`libtschat_client_lib.so` shim), is separately pinned by SHA-256
`fa3219fe261a394ef7167d660352f6409489e6177058b9a087e1a03ecdda89ef`.
Useful Go function addresses:

```text
0x557dc0  matrix.CheckLogins
0x567700  matrix.Login
0x570760  matrix.Sync
0x56afa0  matrix.SendMessageEncrypted
0x56c3e0  matrix.ExportSessionToMyTSCloud
0x56cd20  matrix.ImportSessionFromMyTSCloud
0x560360  matrix.CreateGroupSessionFromSharedData
0x9e13c0  client.(*MatrixClient).Connect
0x9f7000  client.(*MatrixClient).login
0xa0eea0  client.(*MatrixClient).decryptEvent
0xa10019  call to myts.RequestFromMyTSCloud inside decryptEvent
```

Go names can be recovered from its Go 1.21 `pcHeader` at **file offset
`0xe2d300`** (`f1 ff ff ff 00 00 01 08`). Its header has `nfunc=16105`,
`textStart=0x22ca40`, relative function-name table `0x60` and relative
`pclnOffset=0x386c40`. Each function-table entry is two little-endian u32s,
`entryOffset, funcOffset`; the `_func` record's second u32 is its signed name
offset. Resolve function starts against `textStart`, names against the name
table, and `_func` records against the pcln table. ELF mapping matters: the
data section's virtual address is not its file offset.

Native Go JSON struct metadata corroborates the wire fields: `loginRequest`
type `0xd729e0`, `LoginData` `0xd72860`, credential intermediate `0xd72aa0`.
These are static types, not captured request/account data.

## 7. Repeatable offline verification

The new research files are:

- `tools/myts/chat_session_vectors.py`: fabricated plaintext/key and independent
  PyCryptodome envelope encoder/decoder, reusing the existing item reference.
- `tools/myts/test_chat_session.py`: round-trip, framing and malformed-input
  tests (not by themselves an independent compatibility oracle).
- `tools/myts/gdb_chat_session_synthetic.py`: actual desktop crypto helpers
  compared with that independent implementation, in both directions.

```bash
captures/myts/.venv/bin/python -m unittest discover -s tools/myts -p 'test_*.py'
unshare -Urn env MYTS_HOST_NETNS="$(readlink /proc/self/ns/net)" \
  MYTS_BINARY="$PWD/../teamspeak/TeamSpeak" \
  gdb -batch -nx -x tools/myts/gdb_chat_session_synthetic.py ../teamspeak/TeamSpeak
```

**Observed:** 33 Python tests passed; native/reference comparison passed for
synthetic session JSON, a one-byte plaintext and a multi-block binary plaintext.
The native decoder rejected changed IV, ciphertext, digest, an 80-byte truncated
frame and a wrong account key. Only generated inputs were used. The inferior
was stopped before entering application main, then killed; the runner fails
closed on the wrong binary or a non-isolated network namespace. Dynamic-loader
and global initialization still run, as in the earlier identity oracle.

This specifically proves the **outer wrapper**. The fabricated session JSON
contains invalid placeholder Megolm keys on purpose; it is not evidence of a
successful native group-session import or a complete history restoration.

### 7.1 Valid synthetic Megolm follow-up

New files:

- `tools/myts/megolm_synthetic.py`: narrow ctypes adapter to the supplied
  `../teamspeak/libolm.so.3`, with explicit ABI signatures and hash preflight.
- `tools/myts/test_megolm_synthetic.py`: seven offline tests using valid generated
  sessions and fabricated `m.room.message` plaintexts. Keys, entropy, sender
  metadata and content are deliberately public synthetic data, unsafe for use
  outside these tests.

The pinned libolm SHA-256 is
`aeedb3e134c7976f194aa156847a6a6c9889df6983e017c4bbd7f6a40470459c`.
These tests require that external desktop library and fail closed if it is
absent or changed; they do not fall back to a system-installed version.

```bash
unshare -Urn captures/myts/.venv/bin/python -m unittest discover \
  -s tools/myts -p 'test_megolm_synthetic.py' -v
captures/myts/.venv/bin/python -m unittest discover -s tools/myts -p 'test_*.py'
```

**Observed:** all seven new tests passed in an isolated network namespace;
the complete research suite passed **40 tests**. Established:

1. Synthetic JSON for types 1/2 with a valid sharing key, and type 3 with a
   valid exported key, survived the demonstrated Python envelope wrap/unwrap
   and reconstructed dispatch, and fresh libolm receive sessions decrypted
   four synthetic messages with the expected session ID and indices.
2. Decoded sharing keys were 229 bytes with version byte `0x02`; exports were
   165 bytes with version byte `0x01`. Passing either to the other's libolm
   initialization mode failed.
3. A receive-session export at index 2 cannot decrypt messages 0/1; a sharing
   key can also start after index 0. See §5.1.
4. An exported receive session initially has libolm's internal `is_verified`
   flag false, and successful message decryption changes it to true. This flag
   is **not verified Matrix device/user identity**, nor an authenticated cloud
   wrapper or forwarding chain.
5. libolm alone accepted decrypting the same message/index twice. Application
   replay bookkeeping is required. A changed message signature was rejected.

**Evidence limit:** both Megolm key generation and message decryption used the
same bundled libolm. This is not an independent cryptographic implementation.
The JSON/envelope dispatch here is research Python; no native Go JSON importer,
Flutter persistence, Matrix timeline retrieval, or real-history restoration was
exercised. The earlier independent C++ oracle remains evidence for the outer
wrapper only.

## 8. Availability and next implementation gates

Public follow-up through the already healthy gateway in `~/infra/wstunnel-gw`:

```bash
docker exec wstgw-demo-1 curl --silent --show-error \
  --connect-timeout 10 --max-time 25 --max-redirs 0 --max-filesize 262144 \
  --proto =https --output /dev/null \
  --write-out 'HTTP %{http_code} TLS %{ssl_verify_result}\n' \
  https://chat-5.tmspk.net/_matrix/client/versions
```

The command returned `HTTP 503 TLS 0`; a separate GET of `.../r0/login`
returned the same generic unavailable HTML. No gateway restart, route change,
port scanning, insecure fallback or authenticated request was used.

These were the original implementation gates. The public reachability and
password-login portions of gate 3 are now demonstrated (§10). Ordinary plaintext
history retrieval is demonstrated in §12, and single-event cloud restoration
is demonstrated in §14. Complete encrypted history and app integration are not. The
earlier cleanup prerequisite was explicitly relaxed by the owner in §12. This
does not authorize deleting unidentified devices or repeating new logins.

Remaining implementation gates:

1. Implement/test bounded cloud-session decoding in Rust using this now-proven
   wrapper, strict JSON types/IDs and synthetic valid Megolm fixtures. Do not
   enable cloud writes as a side effect.
2. Select a Matrix implementation with persistent device/Olm/Megolm state and
   an import interface supporting both sharing and exported session keys.
   Validate TeamSpeak-specific presence and cloud trust handling separately.
3. Extend the §14 own-account type-1 demonstration to an authorized incoming
   sender, nonzero indices and rotated sessions. Do not infer that missing
   identity metadata is acceptable for every backup. Reuse the protected
   research device rather than creating another login, and do not assume logout
   is supported by this deployment.
4. Extend the demonstrated cache-free, single-event recovery to bounded older
   history and independent desktop/content comparison. Preserve sender-device
   trust, forwarding-chain and replay distinctions. §14 validates room, actual
   session ID, index and successful authenticated Megolm decryption, not complete
   history, all import modes live, or an exact plaintext-body comparison.
5. Only then add sending, automatic key publication/backup, background sync,
   notifications, logout and account-switch behavior with their own tests.

No production SDK choice or app chat implementation is made by this research.
Do not overwrite the ongoing contacts/avatar changes or ship Python research
crypto in the application.

## 9. Authorized account recheck and empty-selector cloud query

The owner explicitly authorized using the test account in `.env` for further
research. A new bounded read probe ran through the existing healthy
`container:wstgw-gw-1` namespace, with verified TLS, no redirects, decompressed
response limits, finite deadlines, and aggregate-only diagnostics. The project
mount was read-only. The ignored temporary program is
`captures/myts/history_live_probe.py`; it contains no embedded credentials.

**Observed in this second follow-up:**

The following results precede the User-Agent correction and later Matrix login
in §10. Statements about no Matrix device being created apply to this probe
only, not to the final session state.

- myTeamSpeak password login returned application code **200**. Version-2
  account-key unwrap and an unchanged read-only CONFIG pull succeeded; sync
  status was **301 (`NOT_IN_SYNC`)**, with one complete chat credential record.
- `getActiveIdentifierList` returned application code **1**, two mappings, and
  one distinct own Matrix ID matching CONFIG's username. That returned ID was
  used for the cloud query; no Matrix ID was invented from a guessed domain.
- Both public `/_matrix/client/versions` and `/_matrix/client/r0/login` at the
  freshly account-declared host returned **HTTP 503**, non-JSON, 108 bytes.
  Therefore no generated chat password was submitted, no Matrix login/sync
  occurred, and no Matrix device/token was created.
- `getGroupSessionData` with a populated authenticated own `matrix_id` and
  **zero `group_sessions` selectors** returned HTTP 200, 188 bytes,
  **`error.return_code=1`**, a nonempty error-message field, and **zero entries**.
  The free-text field was not logged. Determine success from the enum, not the
  presence/absence of that text.
- The newly created myTeamSpeak session was deleted in `finally`; cleanup
  returned application code **204**. Existing sessions were not deleted.

The empty-selector result proves authenticated RPC acceptance, **not** that
the account has no backed-up keys. It remains unknown whether empty selectors
mean “nothing requested” or “list all” for this service. Do not use this result
to display “no chat history” or conclude that automatic restoration is absent.
No real cloud envelope was returned, so no real Megolm key was unwrapped.

**Next decisive live experiment:** obtain a bounded encrypted Matrix event
from an authorized timeline, use its exact `(room_id, session_id)` pair in a
targeted `getGroupSessionData` request, match the response, unwrap/import the
key, and compare the decrypted event without logging content or key material.
The 503 appeared to be the blocker at that point; §10 overturns that diagnosis.
The remaining observation is an empty successful initial sync, plus unresolved
temporary-device cleanup. Do not guess other users' IDs, scan alternative hosts,
reset keys, or overwrite local caches to bypass it.

## 10. User-Agent correction and first successful Matrix login/sync

### 10.1 Controlled public comparison

The owner reported that the official desktop on this same PC, without the
tunnel, was exchanging **new account-chat messages**, not merely displaying
cached history. This is owner evidence, not an independently captured desktop
message. It prompted a direct/request-shape comparison rather than further
assumptions about an unavailable server.

Public requests to the same `https://chat-5.tmspk.net/_matrix/client/r0/login`
were run without credentials, redirects, proxy-environment inheritance, TLS
bypass, route changes or gateway restarts. A controlled Python requests test
on Linux/WSL gave:

| Request variation | HTTP | Body |
|---|---:|---|
| Default Python User-Agent | 503 | 108-byte generic unavailable HTML |
| Only `User-Agent: Go-http-client/1.1` changed | **200** | 78-byte JSON login flows |
| Only `Content-Type: application/json` added | 503 | Same 108-byte HTML |
| Go User-Agent plus JSON Content-Type | **200** | Same 78-byte JSON |

The successful flows were `m.login.password` and `m.login.application_service`.
The public versions response advertised versions through `v1.6`. No token was
needed for either request.

Corroboration:

- Direct Linux/WSL curl, default UA: versions/login 503, TLS verification 0.
- Native Windows curl, no tunnel, default UA: versions/login 503, TLS result 0;
  Go UA plus JSON Content-Type: login 200, TLS result 0.
- Existing gateway curl with **only** Go UA: login 200, TLS result 0.
- Direct Linux/WSL curl with **only** Go UA: versions 200, TLS result 0.

Windows process names, established remote socket endpoints and relevant DNS
cache entries were also inspected read-only. No process memory, desktop account
profile/database, network interception, GUI control or application restart was
used. Those connection metadata alone did not establish which request succeeded.

Reproduce the public successful login-flow request without credentials:

```bash
curl --silent --show-error --noproxy '*' \
  --user-agent Go-http-client/1.1 \
  --connect-timeout 10 --max-time 25 --max-redirs 0 --max-filesize 262144 \
  --proto =https --output /dev/null \
  --write-out 'HTTP %{http_code} TLS %{ssl_verify_result}\n' \
  https://chat-5.tmspk.net/_matrix/client/r0/login
```

This isolates a **User-Agent-dependent response**, not its infrastructure cause.
Do not assert an IP ban, Cloudflare rule, authentication bypass, server outage,
or that this exact UA is the only acceptable string. The desktop's actual
runtime UA was not captured. The supplied native library uses Go net/http;
`matrix.setRequestHeaders` at `0x5585c0` handles Authorization and Content-Type,
while request construction at `0x558860` calls `http.NewRequestWithContext`.
Using the Go default UA is empirically compatible with the tested service.

The previous gateway/phone 503 observations remain real, but **they did not
control this variable**. They do not establish a service-wide availability
failure. No corrected-UA phone/Flutter check has been performed.

### 10.2 Authorized authenticated probe after correction

The ignored `captures/myts/history_live_probe.py` was extended to send the Go
UA on Matrix requests, and an explicit `--timeline` option was added. The
existing healthy gateway namespace was used. The project and pinned libolm
were mounted read-only. Responses stayed bounded, TLS stayed verified, and
credentials/tokens/IDs/content were not printed or written to new captures.

Observed sequence:

1. myTeamSpeak login **200**, CONFIG pull **301**, account-key unwrap successful.
2. Active-identifier list **1**, two mappings; a single distinct own Matrix ID
   matching CONFIG's username was selected for response validation.
3. Matrix public versions **200**, JSON, 857 bytes; `r0/login` GET **200**, JSON,
   78 bytes.
4. Matrix `r0/login` POST with `m.login.password`, `m.id.user` identifier and
   generated CONFIG chat password: **200**, JSON, 271 bytes. Its returned user
   matched the expected own identifier; access token and device ID were present.
   No `device_id` or display name was supplied, so a new device was created.
5. `r0/sync` GET: **200**, JSON, 238 bytes, valid `next_batch`, **zero joined
   rooms and zero encrypted events**. It was an initial sync, without `since`,
   with `timeout=0`, `set_presence=offline`, an inline filter requesting up to
   three `m.room.encrypted` timeline events per room, and restricted state/
   account-data/presence filters. No explicit presence PUT was sent; do not
   claim the sync's presence parameter has no possible presence side effect.
6. Cleanup `r0/logout` POST: **404**, JSON, 59 bytes. The script raised before
   its planned token-revocation check and before reaching the targeted cloud
   recovery function. Therefore **no targeted cloud request, real cloud key
   import or message decryption happened in this run**.
7. Outer `finally` deleted only the new myTeamSpeak session: **204**.

Do not interpret this initial empty sync as proof that the test account has no
history. The filters, account correspondence with the owner's desktop test,
room membership/invites, and deployment behavior have not been reconciled.
No unfiltered comparison, pagination, room-list account-data investigation,
device/one-time-key upload, message send, to-device request or cloud write was
performed. In particular, no need to upload keys to obtain rooms has been proven.

Subsequent **unauthenticated** endpoint checks with the corrected UA found:

- POST `r0/logout`, `v3/logout`, and `r0/logout/`: **404 `M_UNRECOGNIZED`**.
- GET `r0/devices`, `v3/devices`, and `r0/account/whoami`:
  **401 `M_MISSING_TOKEN`**.

The latter indicates protected routes exist, **not** that device listing,
deletion, UIA authentication or revocation succeeds with an authenticated token.
No authenticated device-management request was made before the owner stopped
the session. The desktop also has a static `matrix.Logout` at `0x568020` using
the r0 logout route; its existence does not prove deployment support.

## 11. Earlier stop state, cleanup warning and next-session priorities

**Historical checkpoint:** §12 records the owner's later authorization and
relaxation of the cleanup prerequisite. The warning about the earlier unknown
device remains valid; its identity/token were not recovered.

**The owner explicitly requested stopping all tests and preparing this handoff.**
All live commands had completed. No continuing/background research task,
desktop process instrumentation, or pending authenticated request was left
running by this session. Documentation-only edits followed the stop request.

### Unresolved temporary Matrix device/token

- Exactly **one Matrix login was performed by this investigation**. It created
  a temporary device; no device/one-time keys were uploaded for it.
- Logout failed with 404. **The token/device must be treated as potentially
  still active.** Successful myTeamSpeak `deleteSession=204` does not prove
  revocation of the separate Matrix token.
- The token and device ID were kept only in the now-exited probe's memory,
  never logged or persisted. They cannot simply be reused from a fixture.
- The sanitized execution output is locally available at
  `/home/rod/.local/share/opencode/shell/fc85eeca3881c4a6be40420c7f77a0678a3d58e2/sh_13e80d4b7001ojPecibmgSxe88.out`.
  Its filesystem completion time was **2026-10-15 07:39:54 UTC**. This is an
  approximate run reference, not an exact login timestamp or unique device ID.
- No subsequent login, authenticated device list or device deletion occurred.
  Do not identify/delete a device solely from a guessed timestamp or revoke
  all account sessions as a shortcut. Preserve existing desktop/phone devices.

### Resume deliberately, not by rerunning the script

1. Discuss the cleanup limitation with the owner and establish a safe way to
   identify/revoke **only** the research device. Standard protected device
   routes are a lead, not verified cleanup. If identification is ambiguous,
   ask the owner rather than deleting candidates.
2. Before another Matrix login, design and test cleanup, preserve the new
   device ID in an account-scoped secure manner if necessary, and use an
   unmistakable research-only device label. Avoid orphaning further devices.
   Never use `/logout/all` or clear keys/history to simplify research.
3. Diagnose the empty sync with minimally broadened bounded read requests and
   confirm which authorized account/room the desktop observation concerns.
   Do not ask the owner to paste message contents or credentials into chat.
4. Once an encrypted event is obtained, use only its real `(room_id, session_id)`
   to request the cloud backup, validate associations and actual Megolm session
   ID/index, and attempt decryption without logging contents/keys. Comparison
   against the desktop and full forwarded-key trust handling remain separate.
5. Only after protocol evidence is sufficient, plan the Rust/Flutter work. No
   production chat code, Rust change, APK build/install, app-data reset, cache
   copy, or UI change was performed in this investigation.

Local tooling status:

- `tools/myts/megolm_synthetic.py` and `test_megolm_synthetic.py` are new offline
  research files from this session; **40 tests passed**, including seven new
  Megolm tests. The native C++ envelope oracle was not rerun in this session.
- `captures/myts/history_live_probe.py` is ignored, temporary, and **not safe to
  rerun blindly**: its current logout code still assumes a successful r0 logout.
  Its targeted recovery branch exists but was never reached/live verified.
- `/tmp/opencode/myts_go_inspect.py` is a temporary read-only disassembly/name
  annotation helper, pinned to the supplied Go ELF; not a production tool.
- Existing uncommitted contacts/avatar/Flutter/FRB and documentation work was
  preserved. No commits were made. Rust checkout is `../ts6-lib`; desktop ELF
  and bundled libraries are under `../teamspeak`.

## 12. Authorized resumption: filter diagnosis and plaintext history

### Authorization and device lifecycle

The owner could not find a desktop device-management screen and explicitly
decided to leave the earlier device alone, making targeted revocation a
**nice-to-have rather than a prerequisite**. The owner then authorized the
proposed bounded live research: one new identifiable Matrix login, read-only
room/history diagnosis, and a single-event targeted cloud-key read if an
encrypted event could be obtained. This is not permission to delete guessed
devices, use logout/all, publish keys, send messages, change memberships or
enable encryption on an existing conversation.

The new ignored runner is `captures/myts/history_resume_probe.py`; the earlier
`history_live_probe.py` was neither executed nor overwritten. The runner:

- Uses verified HTTPS directly from Linux/WSL with the demonstrated Go UA for
  Matrix, no inherited proxies, no redirects or automatic request retries.
- Bounds requests, decompressed bytes, item/event counts and operation time.
  Logs fixed action labels and aggregates only, not URL paths containing IDs,
  response bodies, credentials, tokens, keys, identifiers or message content.
- Durably records a random research-only device-ID intent before its single
  login and asks for the display name `TS6 Droid history research (temporary)`.
  The returned ID **matched the requested ID**; display-name persistence was not
  separately queried. Own user and device were validated by `whoami`.
- Stores only login/recovery bookkeeping under ignored
  `captures/myts/history-research/`: owner-only directories **0700**, atomic,
  fsynced files **0600**, no symlink-following state reads. The record contains
  a Matrix access token and must never be printed, attached or committed.
  **This is permission-protected local storage, not an encrypted OS vault.**
  It contains no account key, generated chat password, Megolm key, event or
  plaintext history. Core dumps are disabled in the live process.
- `--resume` reuses the protected login record and checks its account/host
  against freshly read CONFIG. **Exactly one new Matrix login occurred in this
  resumption; the two later runs reused that token/device.**
- Keeps the Matrix device deliberately available for the next experiment. A
  separate exact-device cleanup mode exists and has mocked tests only: it was
  **not invoked live**, and no TeamSpeak device-deletion support is claimed.
  Every new myTeamSpeak session in these three runs was independently deleted
  with application code **204**.

Across the earlier investigation and this resumption, two research Matrix
devices have been created: the older one is unidentified and potentially active;
the newer one is active, identified and protected locally. No existing
desktop/phone device was altered, and neither research device published keys.

### Live evidence: why the old sync was empty

Login, account-key unwrap, CONFIG read and own-identifier validation succeeded.
The two mapping records still resolve to one distinct CONFIG-matching own Matrix
ID, including a primary mapping. This validates the probe's account linkage,
not correspondence with a separate desktop profile that has not been inspected.

All Matrix reads below returned HTTP 200 unless noted. Initial sync requests
used no `since`, `timeout=0`, and `set_presence=offline`, as in the earlier probe.
No explicit presence PUT was sent; the sync parameter can affect presence.

| Read | Observed |
|---|---|
| Previous restrictive inline filter, unchanged | 238-byte response; zero joined/invited/left/knocking rooms, timeline or to-device events |
| Broader filter, five timeline events, lazy state membership and included left rooms | One joined room, one `m.direct` room, two global account-data events; timeline contains three `m.room.message` and two membership events; no encrypted events |
| No inline filter | One joined room, ten timeline events, three `m.room.message`; no encrypted events |
| `r0/joined_rooms` | Exactly one joined room, also present in broader sync |
| Own `account_data/m.direct` | One referenced conversation, consistent with sync |
| Room state in broader sync | Seven state events including creation, memberships, permissions and visibility; no `m.room.encryption` |
| Room `state/m.room.encryption` | HTTP 404; error code was not recorded, so this route result alone is not proof of absent encryption |
| Backward `/messages`, no type filter, limit 10 | Three bounded pages: **10, 3, 0 events**; three `m.room.message` in total, with text `msgtype`/string `body`, no algorithm/ciphertext/session/sender-key fields; no `m.room.encrypted` or encryption-state event |

Messages were ordinary plaintext **at the Matrix event layer**, transported
over verified HTTPS. Their bodies were not logged or persisted. This is not
Megolm decryption or evidence of unencrypted network transport.

A final controlled comparison changed **only** the original timeline `types`
field; all other filter fields, authentication and request parameters stayed
the same, using the same saved device/token:

| Timeline types | Joined rooms | Timeline events |
|---|---:|---|
| `["m.room.encrypted"]` | 0 | 0 |
| `["m.room.message"]` | **1** | **3 ordinary message events** |
| `types` absent, same limit 3 | **1** | 3 events: two memberships and one ordinary message |

This directly establishes that the encrypted-only filter hid the visible
conversation. There is no evidence that device-key upload was needed to obtain
rooms: none was done. Do not infer that there is no backup, that another account
has no encrypted history, or that forgotten/inaccessible conversations do not
exist. Scrollback establishes only the history exposed to this account through
the selected room and tested pagination.

### Encryption is a separate desktop action; next decisive experiment

Read-only inspection of the pinned desktop's `html/client_ui/main.js` confirms
the conversation context menu has `chat.action.e2ee.encrypt` (`Encrypt Chat`),
calling `S.enableEncryption()`, for eligible direct/private rooms when the user
has the required admin role. Already encrypted rooms show the disabled
`chat.action.e2ee.is_encrypted` item instead. This is static UI evidence, not
a live toggle or proof of its cloud-upload behavior.

No existing conversation was changed to fabricate an encrypted sample. To
continue, obtain a **disposable encrypted test conversation with a consenting
participant and at least one encrypted message**, or have the owner identify
an already encrypted conversation authorized for this research. Enabling
encryption is a room-state mutation and must not be silently applied to the
current ordinary conversation. Earlier plaintext events do not become Megolm
events merely because encryption is enabled later.

Then reuse the saved device (no new Matrix login), fetch one encrypted event,
and request only its actual `(room_id, session_id)` cloud selector. **No targeted
`getGroupSessionData`, actual cloud-envelope import or real-message decryption
was executed in this resumption**, because no encrypted event was obtained.
Do not issue the earlier empty-selector request as an enumeration shortcut.

### Offline evidence and implementation boundaries

New shareable files contain synthetic data only:

- `tools/myts/history_probe_support.py`: strict JSON/association/bounds checks,
  sanitized event-shape counters, owner-only research state, and single-event
  receive-only cloud validation. It never generates live Olm/Megolm keys.
- `tools/myts/test_history_probe_support.py`: synthetic rejection cases,
  malformed/incomplete login-record survival, permissions, all three import
  modes, actual first-known index and metadata mismatch checks.

The live runner and its mocked control-flow checks remain ignored research aids:
`captures/myts/history_resume_probe.py` and
`captures/myts/test_history_resume_probe.py`. Importing the runner does not
authenticate; explicit CLI mode selection is required. Its cloud branch remains
unverified live. A single-event check is not full timeline replay protection or
a production Matrix/JSON importer; sender-device and forwarding-chain trust
remain unresolved.

Verification, performed with network isolation:

```bash
unshare -Urn captures/myts/.venv/bin/python -m unittest discover \
  -s tools/myts -p 'test_*.py'
unshare -Urn captures/myts/.venv/bin/python -m unittest discover \
  -s captures/myts -p 'test_history_resume_probe.py'
```

**58 protocol/helper tests + 5 mocked runner tests passed.** The latter cover
one Matrix login followed by token reuse, failed sync retaining the record and
cleaning its myTS session, unsupported cleanup, exact-device password UIA, and
read-only filter ablation. They do not prove live deletion support. The pinned
libolm was hash-checked before authenticated operations; only its inbound path
is used live. The independent C++ envelope oracle was not rerun.

No production Rust/FRB/Flutter code, phone profile, app install, existing cache,
contact/avatar implementation or real-account fixture was changed. Only research
helpers/tests and handoff documentation were added/updated.

## 13. Owner-enabled encryption: state verified, awaiting a new message

**Intermediate checkpoint:** the subsequent dummy message and successful
targeted recovery are recorded in §14; no additional message is required to
repeat that established single-event result.

After the §12 report, the owner stated that they had selected `Encrypt Chat`
on the previously unencrypted direct conversation. The research did not perform
that mutation. Two bounded `--resume` runs (the second explicitly requested by
the owner) reused the same protected Matrix token/device. No new Matrix login
or device was created.

Both checks observed:

- The original restrictive sync now includes the one joined room because its
  state contains **one `m.room.encryption` event** with
  `algorithm=m.megolm.v1.aes-sha2`. Its encrypted-only timeline is still empty.
- Room `state/m.room.encryption` now returns **HTTP 200** with the same Megolm
  algorithm, instead of the earlier 404. This establishes the state transition,
  not successful encryption of a message or availability of a cloud backup.
- Broader/unfiltered sync still contains the earlier ordinary message events
  and the new encryption state, with **zero `m.room.encrypted` events**.
- Bounded backward scrollback returns **10, 4, 0 events**: three ordinary message
  events, membership/room state and the new encryption event. No Megolm
  ciphertext/session pair is available for a targeted cloud query yet.
- The run skipped cloud-session recovery, retained the protected Matrix record,
  and deleted only its new myTeamSpeak session, application code **204**.

The next owner action is to send a **new dummy message after enabling encryption**
in this authorized conversation, using a consenting participant. Earlier ordinary
messages do not become encrypted retroactively. No content or keys need to be
shared in the research chat. After that, reuse the saved research device to read
one actual encrypted event and attempt the exact-pair cloud pull/import/decrypt.
No targeted cloud request or real-message decryption has occurred at this stage.

These checks changed documentation only; the existing 58 helper/protocol and
five mocked runner results remain applicable to the unchanged probe code. No
device revocation, message send, key publication, app/profile change or phone
operation was performed by the research agent.

## 14. First live targeted cloud-key recovery and real Megolm decryption

The owner sent a new dummy message after enabling encryption and requested the
recheck. The same protected Matrix device/token was reused throughout. No new
Matrix login, device, key publication or message send by the research agent was
needed. The sender of the selected event matched the validated own account.

### Demonstrated read/recovery sequence

1. myTeamSpeak login, account-key unwrap, unchanged CONFIG pull and own-ID check
   succeeded. Matrix `whoami` confirmed the saved own user/device.
2. The encrypted-only initial sync now returned **one `m.room.encrypted` event**
   with `m.megolm.v1.aes-sha2`, ciphertext, sender key and session ID. The broader
   sync also returned one encrypted event. The collection's count of two is two
   observations across those reads, not evidence of two distinct messages.
3. A targeted `getGroupSessionData` request carried **one actual
   `(room_id, session_id)` selector**, not an empty/enumeration selector. The
   response was HTTP **200**, 1125 bytes, application return code **1**, and
   **one matching entry**.
4. Standard Base64 decode plus the unlocked raw account-key item decoder
   successfully verified the outer plaintext digest and decoded the session
   JSON. Version string, algorithm, requested room/session and integer-index
   checks passed. The envelope digest is still unkeyed, not sender authenticity.
5. The real backup was **type 1**, sharing-key format, with `chain_index=0`.
   Its `sender`, `c25519`, and `ed25519` fields were **explicit empty strings**.
6. After the narrowly scoped metadata handling below, a **fresh receive-only
   libolm session** was initialized using `olm_init_inbound_group_session`.
   Its actual session ID matched the event's requested ID; actual first-known
   index was **0**. Decryption succeeded at message index **0**, including
   libolm's cryptographic message checks. The decoded JSON's inner room matched
   the selected room, with type **`m.room.message`** and an object content.

**Established:** a real event fetched from Matrix can be decrypted by retrieving
its specific myTeamSpeak cloud backup using the already unlocked account key,
without a copied desktop cache, previously cached Megolm key, extra history
password, device-key upload or device-to-device key request. This is a
single-event research demonstration, not a production Flutter implementation
or evidence that the entire account history is recoverable.

The actual message body, event/room/session IDs, account key and Megolm material
were neither logged nor saved. No exact plaintext-body comparison with the
owner-provided dummy string or separate desktop capture was performed; success
means the cryptographic decode and event association checks above, not an
independent content/desktop comparison. The test message's text is deliberately
not repeated in this document or added to fixtures.

### Real-backup metadata correction, not verified device trust

The first strict attempt failed because `history_probe_support.py` required
nonempty backup identity metadata. A second attempt with fixed-label/boolean
diagnostics isolated that failure: wrapper, requested IDs, version and algorithm
all passed, while sender/device identity strings were empty. Three targeted
cloud reads in this follow-up each requested one pair and returned one entry;
only the final attempt completed message decryption. All three runs deleted
only their own temporary myTeamSpeak session, application code **204**.

Read-only reinspection of the pinned Go ELF corroborated that empty strings are
not excluded by the native JSON importer:

- Exporter `0x56c535`/`0x56c53c`, `0x56c5a5`/`0x56c5ac`, and
  `0x56c615`/`0x56c61c` read the stored `GroupSession` sender, Curve25519 and
  Ed25519 string pairs directly before JSON assignment. They do not fill those
  fields from the current device in that common export block.
- Importer sender extraction `0x56d100–0x56d137`, Curve25519 extraction
  `0x56d1cf–0x56d206`, and the corresponding Ed25519 extraction check JSON
  **string type**, not nonempty length or equality with a live event. This is
  static evidence; the native Go importer was not invoked with the real key.

The research helper's default remains strict. A separate own-account context
permits the empty-metadata case **only if**:

- discriminator is type **1** and the authenticated selected event sender is
  the expected own Matrix user;
- all three metadata fields are explicitly `""`, not missing, null, partial,
  mismatching, non-string or synthesized from event fields;
- all wrapper, JSON type/version/algorithm, selected room/session, actual
  libolm session ID, first-known/message index, signature/MAC and inner-room
  checks still pass.

This permits receive-only compatibility research without pretending that the
missing metadata matched. Diagnostics/result explicitly report
`metadata_policy=empty_own_outbound`, `sender_metadata_matched=false` and
`verified_sender_identity=false`. Do not mark a recovered device verified or
make missing-metadata acceptance a general production policy, especially for
other senders or types 2/3. The actual backup's identity strings cannot be used
to bind its sender Curve25519/signing identity; that trust question remains open.

### Verification and remaining gates

The synthetic suite now has **64 protocol/helper tests**, plus the existing
**five mocked runner tests**, all passed in an isolated network namespace.
Added checks cover sanitized diagnostics, explicit own type-1 empty metadata,
strict default behavior, other users/types, missing/null/partial metadata,
actual session mismatch, tampered message signature and wrong inner room.
No real account material was added to fixtures. The pinned libolm remains the
receive implementation, not an independent Megolm implementation. The earlier
independent C++ envelope oracle was not rerun.

Next evidence should distinguish incoming peer messages from own outbound
backups, exercise nonzero indices/rotation/older ciphertext, and establish
sender-device/forwarding-chain trust and replay policy before application
integration. No Rust/FRB/Flutter chat code, phone data or existing contacts/avatar
work was changed. Research-device revocation remains optional, unattempted in
this stage, and unverified; retain/reuse the protected record rather than create
another login.

Protocol references (standard behavior, not proof of TeamSpeak live support):

- [Matrix Client-Server API](https://spec.matrix.org/latest/client-server-api/)
- [Matrix E2EE](https://spec.matrix.org/latest/client-server-api/#end-to-end-encryption)
- [Megolm sharing/export formats](https://spec.matrix.org/latest/olm-megolm/megolm/)
- [libolm inbound C API](https://gitlab.matrix.org/matrix-org/olm/-/blob/master/include/olm/inbound_group_session.h)
- [libolm outbound C API](https://gitlab.matrix.org/matrix-org/olm/-/blob/master/include/olm/outbound_group_session.h)

## 15. Two disposable accounts: encrypted sending works; incoming backup absent

**Historical checkpoint.** The owner's subsequent desktop failure report led
to the key-delivery correction and successful incoming cloud recovery in §16.
The absent backup here was not proof that official clients could process the
original standard-only key event, or that the cloud service was broken.

### Authorization and scope

The owner added a second account and both usernames to the ignored `.env`,
explicitly clarified that the peer was no longer the previously named person,
and authorized autonomous testing between the two disposable accounts. Accounts
were selected using their respective email/password fields. Actual Matrix IDs
and HTTPS hosts were obtained from decrypted CONFIG and active-identifier
responses, not guessed from `USERNAME`/`USERNAME2`. Both accounts passed password
login, account-key unwrap, CONFIG and own-identifier checks, and their Matrix IDs
were distinct.

The experiment was isolated to one newly created private encrypted test room
containing exactly these two accounts. No existing conversation was modified,
no contacts were changed, and no Flutter/phone/profile data was accessed. This
authorization newly included a sender research device's public identity-key
upload, consuming a bounded number of recipient one-time keys, Olm-encrypted
room-key sharing, room creation/join and three encrypted dummy sends. Earlier
sections' statements that research performed none of these writes describe
their earlier stages only.

### Device/key lifecycle and research implementation

- Account 1 reused the protected device/token from §12. No new Matrix login or
  public-key upload was performed for that recipient research device.
- Exactly one new Matrix device was created for account 2, with a durable random
  ID intent and research label. Its returned ID matched the requested ID, and
  `whoami` validated its own user/device. All subsequent runs reused this record.
  No existing/unknown device was deleted or reset; revocation was not attempted.
- Device self-signatures and signed one-time-key signatures were checked with
  the pinned desktop libolm. These checks are **not cross-signing or out-of-band
  verification of the account/device owner**.
- `tools/myts/research_olm.py` is a narrow research adapter, not application
  crypto or a production Matrix SDK choice. It generates identity, Olm and
  Megolm entropy using the OS CSPRNG, never the deterministic synthetic helper's
  outbound generator. Its inbound/group primitives use the pinned libolm.
- The sender's Olm account, post-send pair sessions and advancing Megolm ratchet
  are retained only as encrypted libolm pickles under its existing owner-only
  ignored research record. The pickle key is the account's unwrapped 32-byte
  account key, freshly derived/unlocked in memory, never stored in that record.
  The file also contains its Matrix bearer token, IDs, idempotent transaction
  bookkeeping and encrypted event/to-device payloads. Thus **the overall record
  is permission-protected, not a fully encrypted OS vault**. Directory/file
  permissions were checked as 0700/0600. Do not print, attach or commit it.
- No raw account key, generated chat password, decrypted cloud envelope, Megolm
  sharing key, decrypted history or response bodies were logged or added to
  fixtures. Only synthetic test content was generated for outgoing encryption.
- Every temporary myTeamSpeak session in every live run was deleted with code
  204, including the initial interrupted send run. The distinct Matrix research
  tokens/devices remain intentionally retained for reuse.

Local ignored orchestration is in `captures/myts/two_account_probe.py` and
`captures/myts/two_account_exchange.py`. A durable phase fence prevents accidental
new room/key creation when an exchange intent already exists. The current sender
record at this checkpoint had `exchange.phase=cloud_not_available` and exactly three accepted events.
Do not rerun `--exchange`; `--recover` reuses those events/session/device and only
performs authenticated lookups and targeted recovery (apart from temporary myTS
login/cleanup and a sync's possible offline-presence effect). It never uploads a
cloud backup. The older single-account runner remains unchanged.

### Live observations

1. Before the sender upload, public-key query returned five Olm-capable device
   records for account 1 and two for account 2. The new sender device made the
   latter three. This does not establish that any official desktop was online.
2. Public sender identity-key upload, private encrypted room creation and
   recipient join all returned HTTP 200. Membership and Megolm encryption state
   were checked independently through both account tokens.
3. One-time-key claim and Olm room-key submission returned HTTP 200. The key was
   encrypted separately to **five account-1 devices and two other account-2
   devices**, with signed-key checks before sharing. Server acceptance is not
   proof those clients processed the key or backed it up.
4. Exactly **three `m.room.encrypted` dummy events** were accepted. The same
   session ID and sender device were used at Megolm indices **0, 1 and 2**. A
   fresh local inbound session checked each generated ciphertext against the
   exact known dummy plaintext/index. This is a same-libolm sender-side check,
   not a recipient-cloud restoration or independent desktop comparison.
5. Account 1 retrieved all three actual accepted events and their exact
   ciphertext/content matched what account 2 sent; sender/event IDs and encrypted
   event type were checked. No plaintext message was sent to the Matrix timeline.
6. Immediate single-event reads sometimes returned **404 `M_NOT_FOUND`**. The
   first accepted event later returned HTTP 200 from the same route; other
   just-sent events were visible through bounded scrollback when immediate
   sync/single-event retrieval did not expose them. Therefore **do not call the
   endpoint unsupported**, or treat one immediate 404/empty sync as absent
   history. The initial run stopped after the first accepted send; continuation
   restored the encrypted ratchet and sent only messages 1/2, without resending
   message 0, changing devices or creating another room/session.
7. Four recipient `getGroupSessionData` calls, ten seconds apart, each selected
   the **same exact real room/session pair**. All returned HTTP 200/application
   code 1, but **zero entries**. No incoming backup JSON/key was available to
   validate or decrypt. The strict metadata policy and own-type-1 exception
   remain unchanged. The experiment deliberately did **not** upload its own
   constructed backup, which would make an official-backup compatibility claim
   circular.

**Established:** controlled account-to-account encrypted event submission and
recipient retrieval, a persistent sender ratchet surviving a process boundary,
and local plaintext/index checks through index 2. **Not established:** recipient
Olm key processing, official desktop display, incoming type-2/3 cloud backup
semantics, cloud-recovered plaintext comparison, sender-device trust, rotation,
full history or production/app messaging. Zero backup entries do not establish
why the backup is absent, whether an official client was online, or that the
service cannot back up incoming sessions.

### Verification and next decisive step

Network-isolated checks passed: **69 shareable protocol/helper tests**, the
existing **5 single-account mocked runner tests**, and **7 new two-account
runner tests** (81 total). The new coverage includes distinct CSPRNG keys,
signature tampering, encrypted pickle/wrong-key handling, actual Olm pre-key
delivery followed by Megolm indices 0/1/2, restored nonzero group ratchets,
device-signature/user binding, empty-recipient-key rejection, HTTP failures,
read-only 404-to-sync fallback, intent fencing, and continuation that does not
resend an accepted event. These tests do not establish live recipient decryption.

Next, have an official desktop for **account 1 (the first email in `.env`)**
connected and processing the newly created `TS6 Droid disposable encryption test`
room; verify that it can display the three dummy messages. Then run the bounded
`--recover` path against the same existing pair. If a backup appears, validate
incoming metadata without extending the own-type-1 exception, check the actual
session/index and controlled sender public keys, and compare all three decoded
messages exactly in memory. If it remains absent, investigate official receive/
backup behavior rather than uploading an artificial fixture or resetting keys.
No new login, additional dummy message or session rotation is required merely to
retry that cloud read. Rust/Flutter integration remains a separate phase.

## 16. Desktop key-delivery correction and incoming type-2 recovery at indices 3–5

### Reported failure and bounded diagnosis

The owner opened the official client and reported `Currently unable to decrypt
message - Retry`, then `Waiting for keys`. This independently established that
the timeline events reached the desktop but did **not** establish that it could
process the research key share. The follow-up reused both protected Matrix
devices and the existing room/session, without new login or reset.

Bounded authenticated reads found:

- All five original account-1 target devices and both original other account-2
  devices still published the same signing/Curve25519 keys. There were no new
  untargeted published devices and no changed public keys among those targets.
- Each account had a recently active previously targeted device according to
  device-list metadata; this alone did not establish receipt or decryption.
- Initial research-device syncs exposed `m.room_key_request` events for the exact
  test room/session from both account users. Counts included observations through
  both research devices, not necessarily distinct logical requests. No arbitrary
  key request was answered or used to select a new recipient.
- One additional exact-pair recipient cloud read still returned zero entries.

Diagnostics did not publish keys, send timeline/to-device messages, acknowledge a
new incremental sync cursor, or alter app profiles. A sync still requested
offline presence and can have that documented side effect.

### Native compatibility error in the research sender

Read-only static inspection of the pinned Go desktop library identified an
additional TeamSpeak requirement absent from the original standard-only
`m.room_key` construction:

```json
{
  "type": "m.room_key",
  "content": {
    "algorithm": "m.megolm.v1.aes-sha2",
    "room_id": "!synthetic:example.invalid",
    "session_id": "synthetic-session",
    "session_key": "synthetic-placeholder-not-a-valid-key",
    "chain_index": 3
  }
}
```

`matrix.ProcessRoomKeyEvent` at `0x56fe00` reads `chain_index` as the JSON numeric
type at `0x570020–0x57003f`, and its common acceptance path rejects a missing or
non-numeric field at `0x5701da–0x5701e3`, even for a direct `m.room_key`, not only
a forwarded event. The original research sender omitted that field. Its
same-libolm local tests exercised crypto and standard Matrix framing but did not
cover this native JSON compatibility gate: their success was insufficient for
desktop interoperability.

The native `SendToDeviceMessageEncrypted` also adds outer `device_id` and an
optional `session_id` (`0x56f8ad`, `0x56f928`); the corrected wrapper includes
both alongside `algorithm`, `sender_key` and the encrypted payload. The live
correction changed these wrapper labels together with numeric `chain_index`;
there was no separate live ablation of each label. Native parsing establishes
the numeric-field requirement, not a universal Matrix requirement or proof that
each added outer label is independently mandatory.

`tools/myts/research_olm.py:room_key_content` now constructs and type-checks the
numeric field using the actual outbound libolm index. The initial exchange path
also preserves a separate account-key-encrypted initial group pickle before
sending anything, to retain the earliest sharing key for future controlled
research. **That fix cannot retroactively restore the old initial snapshot.**

### Same-session correction, not recovery of the old ratchet

At the end of §15 the sender retained only its advanced outbound group state at
index 3; the original index-0 sharing key was not separately saved. Its encrypted
Olm delivery messages survived, but their inner payload lacked the required
numeric field. The correction did not pretend to reconstruct the earlier secret
or reset the device/session to hide that mistake.

The explicit `--repair-delivery` operation:

1. Revalidated the original signed public-device associations.
2. Restored the **same sender Olm account, existing seven pair sessions and
   existing Megolm ratchet**, still at index 3. No one-time-key claim, new device
   key publication, session rotation or cloud backup upload was performed.
3. Preserved an encrypted index-3 group snapshot separately, for receive-key
   sharing only; that frozen snapshot must never be reused for outbound sends.
4. Shared the current Megolm key through the existing Olm channels, with numeric
   `chain_index=3` and the native-compatible outer labels. The real first-known
   index of that sharing key was 3, not 0.
5. Sent exactly one additional encrypted dummy event at index 3 in the same room
   and session, with durable transaction/ratchet state before submission.

HTTP 200 followed for the share and event send. The owner's next report confirmed
that the official client displayed the known dummy **#3**. This is independent
owner evidence of desktop receipt and plaintext display; no desktop profile,
memory, logs or screenshots were read by the research process.

### Real recipient cloud key and exact plaintext recovery

The first targeted recipient cloud read after compatible sharing returned
HTTP 200/application code 1 and **one exact-pair entry**, not zero. The research
did not upload that backup or pass its local sender sharing-key snapshot into
the recovery function. Recovery used the recipient account's unlocked key,
selected cloud envelope and freshly initialized receive-only libolm session.

Observed real backup/event validation:

| Check | Result |
|---|---|
| Export discriminator | **Type 2**, direct sharing-key initialization mode |
| Version/algorithm/requested room/session | All match |
| `sender` and `c25519` | Nonempty, match the incoming event's sender and sender key |
| `ed25519` | Nonempty, matches the independently controlled sender device's public signing key |
| Own-outbound exception | **Not used**; event sender is the other account |
| Backup JSON `chain_index` | **0** |
| Actual libolm first-known index | **3** |
| Message indices | **3, 4, 5** |
| Inner room/type/content and known dummy plaintext | Exact matches for all three |
| Cross-signing/out-of-band device identity | **Not verified** |

After index 3 succeeded, the bounded `--compatible-followups` mode sent only
indices **4 and 5**, without resharing the room key, creating a device or rotating
the session. The sender ratchet was restored across another process boundary.
The owner independently confirmed desktop display of both #4 and #5. The final
`--recover` run made **one** exact-pair cloud read and decrypted/reconciled all
three events in fresh receive sessions using that returned backup; all exact
known plaintext, index and sender-metadata checks passed.

One immediate read after message 5's accepted send was temporarily absent from
single-event, sync and bounded history surfaces. The run stopped with its event
ID saved. The next recovery read found it; no extra message was sent. Event lookup
now permits at most three read-only attempts, with one-second waits, never
resubmitting an already accepted send. This reinforces the §15 eventual-visibility
caveat rather than establishing an unsupported endpoint.

**Established:** incoming encrypted message interoperability with the official
desktop, independent recipient cloud type-2 key recovery, strict populated
sender-metadata reconciliation and exact content comparison at nonzero indices
3/4/5, with normal session continuation and no research cloud upload.
**Not established:** recovery of original messages 0/1/2, all historical keys,
type-3 forwarding trust, cross-signing, rotation, durable production recipient
state, Rust/Flutter chat or app-level verification.

This is live evidence that **JSON `chain_index=0` does not imply index-0 history
coverage**, even for type 2. The actual first-known index is authoritative.
The first three dummy events are outside the returned key's coverage and must
not be presented as recovered. The narrow own-type-1 exception remains unchanged.

### Final lifecycle, tests and next implementation gate

The same room contains **six** research encrypted events in total, indices 0–5;
only the corrected segment 3–5 is demonstrated on the desktop and from the cloud.
No new Matrix login/device, key reset, room creation, key claim, contact change,
research cloud write, app install or profile deletion occurred in this follow-up.
All new temporary myTeamSpeak sessions, including the interrupted follow-up run,
were independently deleted with application code 204. Matrix research records
remain protected and available; the old unidentified device is still untouched.

The sender record's phase is now
`cloud_recovery_completed_for_repair_only`, with the corrected event and two
followups under `exchange.compatibility_repair`. `--recover` reads that corrected
segment only; it must not relabel the original three events recovered. No further
send is required. `--exchange` remains fenced. CLI modes are mutually exclusive;
only explicit `--prepare` can create account 2's first research device, so missing
state in recovery/diagnosis fails closed instead of silently creating a login.
Private keys/ratchets remain account-key-encrypted pickles, and bearer tokens
remain permission-protected, not an OS-encrypted vault.

New offline coverage includes native-compatible numeric key metadata, actual
nonzero first-known index, corrected delivery over a previously used Olm channel,
same-session message 3, idempotent correction and 4/5 followups, bounded read-only
visibility retry, and mode/device-creation fences. No real message text, account
names, identifiers, keys or tokens were added to fixtures or this document.

The read/recovery production gate is now better supported: implement bounded
Rust envelope/session validation with this **type-2/nonzero-coverage** case,
then select a persistent Matrix crypto integration for Flutter. Sender-key trust,
replay/index handling, partial-history UI and device lifecycle remain explicit
requirements, not solved by successful decryption. Production sending and cloud
key publication remain separately planned work; the authorized research sender
is not shipping application code.

## 17. Owner-requested stop and next-chat handoff

**The owner explicitly requested stopping and preparing a new-chat handoff.**
All live commands have completed. No background sender, polling loop, desktop
instrumentation or pending authenticated operation was left running. After the
stop request, only documentation was updated; no further account requests,
message sends or test commands were executed.

### Evidence to carry forward

- §14 remains the own-outbound type-1 demonstration with explicitly empty
  identity metadata and a narrowly scoped research exception.
- §15 is the initial **failed desktop-interoperability** checkpoint, not evidence
  of a cloud outage or successful recipient decryption.
- §16 is the decisive incoming demonstration: numeric key-share metadata fixed;
  official desktop display of 3/4/5 independently owner-confirmed; exact-pair
  recipient cloud type-2 pull, fresh inbound initialization, strict populated
  sender metadata, matching controlled signing key and exact plaintext at all
  three nonzero indices. No research cloud upload made the result circular.
- There are six research encrypted events in the same room/session, indices 0–5.
  The returned key begins at **3**, despite backup JSON index 0. Do not claim
  recovery of 0/1/2 or all account history. The old initial sharing key was not
  separately retained by the original sender; corrected code now keeps a frozen
  encrypted initial snapshot for future research, never for repeated sends.
- A valid Megolm MAC/signature, matching envelope metadata and the controlled
  sender-key comparison still do not establish cross-signed/verified user-device
  identity. Type-3 forwarding, replay policy and rotation remain open.

### Files and protected runtime state

Shareable research additions/updates relevant to this follow-up:

- `tools/myts/research_olm.py`: CSPRNG sender/account/pair adapter, pinned libolm,
  signature checks, account-key-encrypted pickles and numeric direct-room-key
  metadata. Not production code and not a Matrix SDK selection.
- `tools/myts/test_research_olm.py`: offline crypto/metadata regression tests.
- Earlier `history_probe_support.py`, `megolm_synthetic.py`, cloud envelope
  helpers and tests remain the receive/validation foundation; do not broaden
  their own-type-1 exception to incoming type-2/3 metadata.
- This document, `docs/myteamspeak-contacts-chat-protocol.md` and root
  `AGENTS.md` record the current evidence and limits.

Ignored local orchestration, with no embedded credentials:

- `captures/myts/two_account_probe.py`: entry point, bounded transport/auth,
  both-account linkage, explicit mutually exclusive operation modes.
- `captures/myts/two_account_exchange.py`: original exchange, correction,
  two followups and exact cloud recovery; durable idempotent send bookkeeping.
- `captures/myts/two_account_diagnose.py`: existing-device coverage and bounded
  to-device/key-request diagnostics.
- `captures/myts/test_two_account_exchange.py`: mocked/offline orchestration
  tests, including actual synthetic Olm continuation and idempotent followups.
- `captures/myts/test_two_account_lifecycle.py`: newly added no-login-fallback
  and exclusive-mode checks; **not yet executed** at the stop checkpoint.
- Earlier `history_resume_probe.py` and its five mocked checks remain available
  and were not overwritten. Do not blindly run `history_live_probe.py`.

Both disposable account credentials are in ignored `.env`; do not print/read
their values into tool output, logs, docs, fixtures or chat. `USERNAME` fields
are not a substitute for the CONFIG/active-identifier linkage. Account 2 was the
sender, account 1 the recipient. Actual IDs, tokens, encrypted key/ratchet state,
pair associations and accepted event/transaction IDs are in owner-only ignored
records below `captures/myts/history-research/`. Discover and match these by
freshly authenticated account/host when authorized; never print or attach them.
The account-2 sender has `exchange.phase=cloud_recovery_completed_for_repair_only`
and corrected indices 3–5 under `exchange.compatibility_repair`.

**No send or key share is needed merely to resume the established recovery.**
If another live read is explicitly requested, `--recover` selects only that
corrected segment and reuses the saved Matrix devices. Only explicit `--prepare`
can create the second account's first research device; other modes fail closed
on missing state. Do not use `--exchange`, reset keys, log out all sessions,
delete guessed devices, reinstall/clear the phone app, or rotate the session as
a discovery shortcut. The earlier unidentified device remains unresolved and
untouched. All new temporary myTS sessions were cleaned with code 204; the two
identified Matrix research records deliberately survive. Bearer tokens are only
permission-protected, while private crypto state is encrypted with the freshly
unlocked account key; this is not an OS-backed production vault.

### Executed verification versus later unexecuted checks

The last executed full offline checks, performed in isolated network namespaces,
passed **70 shareable protocol/helper tests + 15 ignored runner tests = 85**.
Those runs covered numeric key metadata, Olm continuation, corrected message 3,
idempotent messages 4/5 and bounded visibility retry, along with previous checks.
The three tests in `test_two_account_lifecycle.py` were added **after** that run
and have not been executed. Do not relabel the result as 88 passing tests without
actually running them. The final mutually exclusive CLI/no-create-fallback change
is likewise not covered by a subsequent executed full-suite run. Documentation
after this checkpoint has not been followed by another whitespace/test command.

For a future authorized **offline** verification only:

```bash
unshare -Urn captures/myts/.venv/bin/python -m unittest discover \
  -s tools/myts -p 'test_*.py'
unshare -Urn captures/myts/.venv/bin/python -m unittest discover \
  -s captures/myts -p 'test_*.py'
git diff --check
```

No Rust/FRB/Flutter chat implementation, build, phone install or production
integration was performed in this follow-up. The working tree already contains
substantial contacts/avatar/Flutter/FRB/documentation work from other sessions;
preserve it. No commits were made.

### Recommended next delivery

Read root `AGENTS.md`, §§14–17 here, the contacts/chat reference, and product
direction before planning. The Rust checkout on this machine is `../ts6-lib`,
not `../tslib`. Move protocol/envelope and bounded session validation into
`tslib-myts` with synthetic fixtures covering own type 1, strict incoming type 2,
actual nonzero first-known coverage, malformed/mismatching metadata, tampering
and oversized replies. Expose it through `tslib-frb`; do not ship the Python
research sender or leak raw secrets through ordinary Dart models/preferences.

Choose a persistent Matrix crypto integration deliberately: both sharing and
exported receive-key import modes, atomic sync/event/key persistence, account/
device isolation, replay-index bookkeeping and explicit trust/partial-history UI
are requirements. Start with reading/recovering history in Flutter. Production
sending, automatic backup publication, ongoing sync/notifications and device/
logout management require their own plan and evidence. Live account/device tests
should be separately confirmed in the new chat, not inferred from a handoff.

## 18. Subsequently authorized Rust/Flutter read-only implementation

After §17 the owner requested a pragmatic first reader with focused tests and
explicitly authorized using the disposable accounts again. See
**[myteamspeak-history-reader.md](myteamspeak-history-reader.md)** for implementation,
security policy, acceptance limits and the current build checkpoint.

The new sans-IO Rust engine uses `vodozemac`, exposed through opaque FRB handles;
Flutter provides manual joined-room/history reads and secure encrypted snapshots.
It does not run Matrix `/sync`, publish keys, send messages or implement an Olm
to-device receiver. Forwarded/type-3 keys remain unsupported. The narrow own-type-1
empty-metadata path is default-off and requires an explicit unlock checkbox.

A newly authorized real read **reused both existing Matrix records**, fetched the
established corrected segment and one real recipient type-2 cloud backup, and
verified exact plaintext 3/4/5 through the **new Rust implementation**. An encrypted
snapshot round-trip in memory preserved decryption; actual first-known index was
3. Controlled sender signing-key matching was checked separately by the research
harness; the app does not claim independently verified/cross-signed device identity.
No Matrix login/device, sync/presence request, send, key publication/claim/query,
cloud upload or protected-record write occurred. Temporary myTS sessions returned
cleanup code 204. Original messages 0/1/2 remain unrecovered.

Focused Rust and Flutter checks passed; the historical Python suite/lifecycle
checkpoint in §17 was not rerun or relabelled. No phone installation/data reset or
real Flutter Matrix login was performed. The research records remain unchanged.
