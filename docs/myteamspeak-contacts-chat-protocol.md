# myTeamSpeak contacts, avatars, account chat and presence

**Research date: 2026-10-15. Implementation target: Flutter.**

**Latest two-account result:** after correcting the research sender's required
numeric `chain_index` in `m.room_key`, the official desktop displayed incoming
messages 3/4/5 and an independent recipient cloud type-2 key recovered all three
with exact plaintext and populated sender-metadata checks. Actual first-known
index is 3 despite backup JSON `chain_index=0`; earlier test messages 0/1/2 are
not recovered. No reset/new device or research cloud upload occurred in that
correction. See [chat-history §16](myteamspeak-chat-history-protocol.md#16-desktop-key-delivery-correction-and-incoming-type-2-recovery-at-indices-35).
Older no-send/no-key-upload statements below describe their original stages.

**Later same-day correction:** the 503 results below were request-dependent,
not proof of an unavailable chat service. On the same endpoint, changing only
`User-Agent` to `Go-http-client/1.1` produced HTTP 200. A later authorized Matrix
password login and initial sync succeeded but returned no joined rooms/events.
**One earlier temporary Matrix device/token may remain active: logout returned
404.** The owner later made revocation optional and authorized further bounded
research. The restrictive encrypted-event filter hid the account's visible
conversation: changing only timeline types reveals one joined room and three
ordinary plaintext message events. After owner-enabled encryption and a new
dummy message, **one real encrypted event was decrypted through an exact-pair
cloud key pull**, using an own-account type-1 backup with explicitly empty
sender/device identity metadata; no verified device identity is claimed. One
additional research device was created and reused,
with its token/ID now retained in ignored owner-only local storage. Read
[chat-history §10–11](myteamspeak-chat-history-protocol.md#10-user-agent-correction-and-first-successful-matrix-loginsync)
for the earlier stop and [§12](myteamspeak-chat-history-protocol.md#12-authorized-resumption-filter-diagnosis-and-plaintext-history)
for the device lifecycle/filter diagnosis and
[§14](myteamspeak-chat-history-protocol.md#14-first-live-targeted-cloud-key-recovery-and-real-megolm-decryption)
for the real recovery, metadata caveat and remaining implementation gates.
Earlier “no Matrix login/device” statements here describe the original
contacts/avatar experiment only.

This reference records demonstrated behavior and the next verification gates.
It does not claim the app already implements these features. Product scope is
governed by [product-direction.md](product-direction.md); password login,
account-key unwrap and item decryption remain governed by their dedicated
references. The existing identity/bookmark importer is described in
[myteamspeak-rust-import-engine.md](myteamspeak-rust-import-engine.md).

## 1. Findings and evidence boundaries

The owner authorized use of the supplied **demo account** for this research.
The probes used the gateway in `~/infra/wstunnel-gw`, sharing its network
namespace rather than changing the host's routes. Requests used verified TLS
and did not follow redirects. Credential values, identifiers, signed URLs,
keys and message content are intentionally absent from this document.

| Capability | Evidence | What it does not establish |
|---|---|---|
| Account contact roster | **LIVE:** `/tschat/getContactList` returned success and one contact with a syntactically valid Matrix user ID | Flutter persistence, display names resolved from Matrix, contact editing or messaging |
| Legacy sync contacts | **LIVE:** `CONTACTS=8` and `GROUP_CHATS=7` had no items, despite the account contact above | That the account has no conversations, groups or messages |
| Chat account configuration | **LIVE:** one decrypted CONFIG item contained complete chat domain/username/password fields | That those credentials are currently accepted by Matrix |
| Own chat identifiers | **LIVE:** `getActiveIdentifierList` returned two mappings, one primary | Identity/bookmark default selection or TeamSpeak server identity selection |
| Avatar metadata | **LIVE:** one returned entry had four state variants and a nonempty signature | Signature verification, image download/decoding or on-device cache behavior |
| Avatar download authorization | **LIVE:** `requestAvatarSignedUrl` returned success and two signed URLs | Successful retrieval of the image bytes; signed-URL expiry/refresh policy |
| Account chat reachability | **LIVE, gateway and phone cellular paths:** the account-declared chat host returned HTTP 503 HTML; the phone's public versions request passed TLS verification | A global outage, account suspension, a permanent protocol incompatibility or authenticated Flutter/Matrix behavior |
| Desktop presence extension | **STATIC:** recovered from the supplied desktop JavaScript | Successful publication/subscription from an independent client |
| Encrypted history restoration | **STATIC:** cloud group-session RPCs and desktop import/export functions exist | Recovery of any actual message or complete history on a fresh device |

No messages, contacts, avatars, presence settings or cloud sync items were
changed. Each myTeamSpeak research session was deleted; cleanup returned
application code **204**. No Matrix login was reached, so no Matrix device,
token or E2EE identity was created. The credentials were retained only in
process memory for the probes, not copied into new captures.

The final sanitized metadata is in ignored
`captures/myts/chat-feasibility-summary.txt`; the temporary research program is
`captures/myts/chat_probe.py`. These are local research aids, not committed test
fixtures or production implementations. The program contains an **unexecuted,
unverified** Matrix login/sync branch: do not treat its presence as evidence.

## 2. Three separate account capabilities

1. **Legacy cloud sync:** identities, bookmarks, CONFIG and optional roster/
   category metadata, carried as encrypted protobuf items.
2. **Chat control plane:** `/tschat` provides account contacts, identifier
   mappings and cloud group-session operations; `/user` provides account avatar
   metadata and signed download URLs.
3. **Matrix data plane:** rooms, direct/group conversations, events, presence,
   memberships and encrypted messaging.

Importing a legacy `Contact` is not a Matrix login. Importing a chat contact is
not restoring its conversations. A `Group_Chats` sync item contains
`category_name`, not the group membership list, room timeline or encryption
keys. Existing TeamSpeak server/channel/private messages are another subsystem
and must not be relabeled as account chat.

Historical statements that System B was permanently out of product scope, or
that CONFIG chat fields must never be inspected, describe earlier research
boundaries. The product direction includes account chat; access to these fields
must still be narrowly scoped, secure and evidence-driven.

## 3. Transport and chat bootstrap

Use the demonstrated myTeamSpeak RPC transport:

```text
POST https://clientapi.myteamspeak.com/<service>
Content-Type: application/ts3cloud
body = u8(method_name_byte_length) || ASCII(method_name) || protobuf_request
HTTP 200 response body = bare protobuf reply
```

Do not parse an HTTP error page as protobuf. HTTP 200 alone is not application
success. Bound incoming **decompressed** bytes, item counts, field sizes and
total deadlines. Do not log response bodies, protobuf debug strings, requests
or exception strings that might contain account data.

The read-only sync request used `requestServerItems`, `sync_version=V1_1`, a
session and class requests 5, 6, 7 and 8. Its reply nevertheless included
bookmarks and identities too: callers must not assume the reply contains only
the requested classes. Decode and classify safely without changing existing
local data.

After account-key unwrap and item decryption, the tested configuration was:

```text
Item_Class.CONFIG = 5
Item_Data.config = field 21
Config_data.tschat_credentials = field 5
Chat_Credentials { domain = 1; username = 2; password = 3; }
Config_data.global_presence_token = field 4    // absent in this sample
Config_data.tschat_de_data = field 7           // present; not investigated
```

The sample domain had no URL scheme; the username was a localpart, not a full
`@user:host` ID. These are sample properties, not universal invariants. Never
hardcode the sample host as the home server for every account.

Chat credentials are **secrets**, even though they arrived inside a sync item
already supported by the item cipher. Keep them in an opaque Rust object or an
account-scoped secure vault if persistence is required. Do not add them to
ordinary bookmark JSON, preferences, analytics or UI diagnostics. The unkeyed
SHA-512 item digest is not an authentication/signature guarantee.

## 4. Account contacts and identifiers (`/tschat`)

The relevant schema is
[`proto/myteamspeak_tschat.proto`](proto/myteamspeak_tschat.proto). Field numbers
below also decoded the current-build live responses in this experiment.

```text
AuthenticatedUser { session = 1; matrix_id = 2; }
getContactList(AuthenticatedUser) -> ContactList
ContactList { repeated Contact contacts = 1; ErrorHandling error_handling = 2; }
Contact {
  ts_chat_identifier = 1;
  note = 2;
  matrix_id = 3;
  repeated MxidHistory matrix_id_history = 4;
}
MxidHistory { matrix_id = 1; initiation_timestamp = 2; }
ErrorHandling { return_code = 1; message = 2; }
CHATREQUESTRETURNCODE_SUCCESS = 1
```

**Observed:** a request containing the session and an empty `matrix_id` was
accepted. The reply contained one contact, a nonempty valid Matrix ID, an empty
`ts_chat_identifier` and no ID-history entries. Do not require a nonempty chat
tag when the Matrix ID is present; do not invent a tag from a display name.
Do not assume `note` is the Matrix profile's display name.

Other read-only calls accepted the same request shape:

- `getActiveIdentifierList`: two own identifier mappings, one marked primary,
  with the account's declared chat host.
- `getAllowedIdentifierList`: two mappings whose Matrix IDs were empty.

The mapping message is
`TschatIdentifierMapping{ts_chat_identifier=1,matrix_id=2,primary=3}`; the reply
is `TschatIdentifierList{repeated ts_chat_identifier_mapping=1,error_handling=2}`.
These lists are not interchangeable with the contact roster. A chat primary
identifier is unrelated to an imported server identity's `is_default` flag.

Independent synthetic request golden, serialized with the recovered current
`AuthenticatedUser` descriptor and the placeholder session `synthetic-session`:

```text
method length = 0e
method = getContactList
protobuf payload = 0a1173796e7468657469632d73657373696f6e
full framed hex = 0e676574436f6e746163744c6973740a1173796e7468657469632d73657373696f6e
```

This contains no account material. Use the full bytes as a request-side golden,
not a second copy of the application's encoder, to catch extra nesting.

For persistence, retain the account owner and full opaque Matrix IDs; do not
key records solely on aliases, note text or a derived myTeamSpeak ID. ID
history and a future home-server move require explicit reconciliation rules.
Never silently merge different accounts or discard a cached roster after an
HTTP/protocol failure. Contact import must not overwrite identities/bookmarks,
generate a server identity or silently complete onboarding.

## 5. Avatars (`/user`)

Sources:
[`myteamspeak_user.proto`](proto/myteamspeak_user.proto) and
[`myteamspeak_avatar_common.proto`](proto/myteamspeak_avatar_common.proto).

### 5.1 Identifying the requested account

```text
requestContactsAvatar(RequestContactsAvatarInfoRequest)
RequestContactsAvatarInfoRequest { session = 1; repeated AvatarRequestID id = 2; }
AvatarRequestID { google.protobuf.Any key = 1; }
AvatarRequestID.MYTSKey { bytes id = 1; }
```

The tested Any type URL was the standard prefix plus the fully qualified type:

```text
type.googleapis.com/com.teamspeak.myteamspeak.proto.user.AvatarRequestID.MYTSKey
```

The desktop `avatar_cache.myTsIdFromMessengerId` Base32-decodes the Matrix
localpart and uses the resulting raw bytes for the myTeamSpeak avatar request.
The tested contact had **trailing `=` Base32 padding**: a decoder restricted to
unpadded localparts would incorrectly skip it. A probe initially did skip it;
after accepting valid padding, the same account returned avatar data.

This derivation is not valid for every arbitrary or decentralized Matrix ID.
Validate syntax and Base32 encoding; do not lowercase, truncate, hash or guess
an unsupported localpart. A placeholder is preferable to requesting the wrong
person's avatar. The schema also declares `KIDKey{string id=1}`, but its
semantics were **not demonstrated** and must not be inferred from the name.

The login's `myts_id_data.my_teamspeak_id` was also available as an own-account
avatar request key. An own-only request returned an empty HTTP 200 protobuf
reply; this did not establish that the own account had a downloadable image.

### 5.2 Metadata and state variants

```text
RequestContactsAvatarInfoResponse {
  repeated AvatarInfoMap data = 1;
  ErrorReturnCode error_code = 2;
}
AvatarInfoMap { AvatarRequestID id = 1; AvatarData info = 2; }
AvatarData { AvatarInfo info = 1; uint64 timestamp = 2; bytes sign = 3; Any optional = 4; }
AvatarInfo { repeated AvatarMap map = 1; }
AvatarMap { AvatarState state = 1; string name = 2; }
```

| Avatar state | Wire value |
|---|---:|
| Invalid | 0 |
| Do not disturb | 1 |
| Online | 2 |
| Away | 3 |
| Offline | 4 |

**Observed:** one signed metadata entry, all four non-invalid states, HTTP 200,
856 response bytes. `error_code` was omitted/default **0**, whose enum name is
`UNKNOWN_ERRORRETURNCODE`, despite the populated data. Do not reinterpret 0 as
an explicit success code; distinguish valid data, an empty response, malformed
entries and explicit errors. Never use the mere absence of an error as proof
that an image was returned.

The signature was **present, not verified**. Do not advertise authenticated
avatar ownership based on this experiment alone. Response-to-request matching,
duplicate IDs, unexpected Any types and malformed entries need bounded tests.

### 5.3 Download authorization and cache boundaries

```text
requestAvatarSignedUrl(AvatarSignedUrlRequest) -> AvatarSignedUrlResponse
AvatarSignedUrlRequest { session = 1; repeated string file_names = 2; }
AvatarSignedUrlResponse { ReturnCode return_code = 1; repeated SignedUrl signed_urls = 2; }
SignedUrl { string file_name = 1; string signed_url = 2; }
ReturnCode.success = field 1
```

Two returned metadata names were submitted; the service returned two signed
URLs and `return_code.success=true`. No image bytes were downloaded during
this research. Signed URLs contain bearer-like authorization material: never
log, document or persist them as permanent avatar identifiers.

An implementation should match returned filenames to the requested set, keep
normal TLS verification, prevent arbitrary/local-network URL fetching, bound
redirects (prefer none), request duration, decompressed image bytes and decoded
image dimensions. Do not forward the myTeamSpeak session, cookies or unrelated
authorization headers to the image host. Account-scoped private caches need
logout/account-switch behavior; shared caches keyed only by a basename are not
safe. URL expiry, renewal and the signed metadata's trust chain are still open.

Do not label an arbitrary avatar state as the user's current online state.
Until presence is available, show a documented fallback image/placeholder and
an **unknown/unavailable** presence indicator, not a fabricated green badge.

## 6. Presence: the desktop extension, not just Matrix's enum

**STATIC source:** `../teamspeak/html/client_ui/main.js`, webpack module
`73829`. `TSChatConnection.internalUpdatePresence` passes the base presence and
the serialized extended state to `tsclient_internal.tschat_setPresence`.

Desktop presence values are:

| Desktop extended value | Meaning | Base Matrix value sent by desktop |
|---:|---|---|
| 0 | Available/Online | `online` |
| 1 | Away | `online` |
| 2 | Do not disturb | `online` |
| 3 | Offline | `offline` |

**These values are different from the avatar enum in section 5.**

The Matrix `status_msg` contains JSON, not just the user's free-form text. A
synthetic example (not captured account data) is:

```json
{"presence":1,"status_msg":"Back shortly"}
```

The extended object can also contain
`servers:[{address,name,uuid}]`. The desktop omits nulls and empty arrays, limits
server advertisements to five and truncates the status text using JavaScript
`substr(0,100)` (UTF-16 code units). Shared-server data is privacy-sensitive:
do not enable advertisement by default or publish existing bookmarks as a
substitute for an explicit user choice.

On receive, the desktop decodes this JSON; a base Matrix `offline` state
overrides any extended value. Without valid extended data it falls back to the
base state. Standard Matrix defines `online`, `unavailable` and `offline`, but
the inspected desktop sender does **not** encode Away as `unavailable` and its
fallback treats non-offline base values as available. A generic Matrix presence
selector alone would therefore not reproduce desktop behavior.

The native library exports `TSChat_SetPresence`; offline Go function-table
inspection resolves `tschat_client_lib/matrix.SetPresence` at ELF virtual
address `0x56daa0` in the pinned library below. It formats the endpoint
`%s/_matrix/client/r0/presence/%s/status` and uses PUT. This is static evidence,
not a successful independent presence update. Background/foreground transitions,
multi-device aggregation, reconnection and Android notification policy remain
implementation/verification work.

## 7. Direct/group chats and encrypted history

The native library exports room listing, direct/group creation, event history,
scrollback and encryption functions. Its Matrix login routine contains both
`m.login.password` and `org.matrix.login.jwt` paths; their mere presence does
not establish which flow this account currently accepts. Discover the live
login flows before building a production authentication path.

Room discovery, memberships, direct-room account data, timelines, pagination
and new-event sync must be demonstrated independently of the contact roster.
Read markers, typing, push, unread counts, room avatars and multi-device
behavior are additional features, not implied by reading the first timeline.

The recovered `/tschat` service declares:

```text
getGroupSessionData(GroupSessionRequest) -> GroupSessionResponse
GroupSessionRequest { AuthenticatedUser user = 1; repeated GroupSession group_sessions = 2; }
GroupSessionResponse { ErrorHandling error = 1; repeated GroupSession group_sessions = 2; }
GroupSession { room_id = 1; shared_session_id = 2; cipher_text = 3; }
```

Desktop exports include `TSChat_ImportSessionFromMyTSCloud`,
`TSChat_AddRequestedGroupSessions` and cloud export callbacks. The Go functions
`matrix.ImportSessionFromMyTSCloud` (`0x56cd20`) and
`matrix.ExportSessionToMyTSCloud` (`0x56c3e0`) refer to Megolm/session material.
This establishes an intended cloud key-transfer mechanism, **not** its outer
cipher/key derivation or a successful restoration. The implementation of that
outer wrapping and its relation to the account key must be traced and tested;
do not assume it is the same framing as a sync item.

For encrypted history, a fresh device needs the appropriate Olm/Megolm keys,
not just a Matrix access token. Keys may not cover every historical message.
No group-session RPC, key import, key request, timeline retrieval or message
decryption was executed in this research. Do not invoke destructive key-reset,
session-clear, account-create or home-server-move operations as discovery probes.

## 8. The 503 and phone/5G comparison

**Historical observations; diagnosis corrected later:** these probes did not
control User-Agent. The same endpoint subsequently returned 200 with the Go
User-Agent on direct Linux, native Windows (with JSON Content-Type), and gateway
paths. Do not infer an outage from the old probes. No corrected-UA phone or
Flutter verification has yet been performed; see chat-history §10–11.

The tested account's declared public service host was `chat-5.tmspk.net`.
Through the owner's tunnel gateway:

```text
GET https://chat-5.tmspk.net/_matrix/client/versions -> 503 text/html
GET https://chat-5.tmspk.net/.well-known/matrix/client -> 503 text/html
GET https://chat-5.tmspk.net/_matrix/client/r0/login -> 503 text/html
GET https://chat-5.tmspk.net/_matrix/client/v3/login -> 503 text/html
```

The HTML was the generic “503 Service Unavailable / No server is available to
handle this request.” This is distinct from DNS/TLS failures and from rejected
credentials. Exploratory requests to HTTPS 8448 and HTTP 8008 timed out; they
did not demonstrate alternate service endpoints. Do not add fallback-port
scanning or insecure HTTP fallback to the app.

The myTeamSpeak control plane worked on the same gateway route. That narrows
the observed failure but does not prove that every route/network fails or that
the chat account requires migration.

### Confirmed USB/phone comparison (2026-10-15)

After the owner attached and authorized the phone, ADB detected a Samsung
SM-S938B. The installed Flutter package was left untouched. Android supplied
`/system/bin/curl`, so no diagnostic APK, new package, credentials or app launch
was needed.

`adb shell ip route get 1.1.1.1` selected **`rmnet_data0`**, the cellular
interface for the shell UID. The mobile-data setting was enabled. The Wi-Fi
setting was also enabled: the evidence is the actual shell route, **not** a
claim that Wi-Fi had been switched off or that every app UID used that route.
The owner described the mobile connection as 5G; radio technology was not
independently measured.

The following public HTTPS request from the phone completed with:

```text
GET https://chat-5.tmspk.net/_matrix/client/versions
curl process exit: 0
HTTP status: 503
ssl_verify_result: 0
elapsed: approximately 0.62 seconds
body: same generic Service Unavailable HTML, not Matrix versions JSON
```

Reproduction (no account information in the command or response):

```bash
adb shell ip route get 1.1.1.1
adb shell 'curl --silent --show-error --connect-timeout 10 --max-time 30 --max-redirs 0 --max-filesize 262144 --proto =https --write-out "\nHTTP %{http_code} TLS %{ssl_verify_result}\n" https://chat-5.tmspk.net/_matrix/client/versions'
```

When constructing `adb shell` commands programmatically, quote the **remote
command** (for example with Python `shlex.join`); passing a write-out format
containing spaces as separate unquoted adb arguments caused a first local
attempt to fail with curl URL-parsing errors. That was not a network result.

The successful cellular probe refutes an **office/gateway-only explanation of
the observed 503**, but does not prove a global outage or diagnose the server's
cause. No authenticated Matrix request, chat password, app transport, room
history or presence operation was tested on the phone. An in-app check remains
a separate verification gate.

### Manual browser comparison, no APK or login needed

1. On the phone, disable Wi-Fi and verify mobile data/5G is active. Existing VPNs
   or proxies can change the route and should be recorded as test conditions.
2. Open `https://chat-5.tmspk.net/_matrix/client/versions` in the phone browser.
3. Record whether it returns JSON with `versions`, HTTP 503 HTML, a TLS error,
   or a timeout. This public endpoint requires no credentials.
4. Never paste account tokens, chat passwords or signed avatar URLs into a
   browser address bar or screenshots shared for diagnostics.

A browser JSON response demonstrates **that endpoint's reachability from that
browser/network**, not a successful app login or E2EE. Repeat with an explicit
bounded app connectivity check before claiming the Flutter transport works.
If both routes return 503, it is not a sufficient basis to call the office
network the sole cause; compare the official desktop/mobile client and service
discovery before guessing a replacement host.

ADB initially listed no devices; the subsequent authorized USB probe is recorded
above. A USB debug connection can remain attached
with Wi-Fi off and 5G active; wireless debugging generally depends on Wi-Fi and
is unsuitable for this clean comparison. Do not automatically toggle the
owner's network, clear application data, uninstall, or replace a signed app to
make a test pass. Use `adb install -r` only after a compatible APK is ready,
preserving the existing data and handling signature/version conflicts safely.

## 9. Implementation and verification handoff

The owner requested a background implementation on 2026-10-15 while the parent
agent documented this research. **At the time of this handoff, implementation
and app-level device verification are still pending.** The public phone curl
test in section 8 is complete; it is not app-level acceptance.

Recommended delivery boundaries:

1. Read-only roster plus avatar metadata/URL/download, account-safe storage and
   localized loading/empty/error UI. Preserve the identity/bookmark flow.
2. Explicit public Matrix reachability test on phone/5G and validated service
   discovery/authentication. No automatic credential retries or cloud writes.
3. Rooms/history/key restoration demonstrated with synthetic tests and a
   narrowly authorized live demo-account comparison.
4. Messaging, desktop-compatible presence, background sync and notifications,
   with their own acceptance tests and session-renewal/key-lifecycle policy.

### Implementation review checkpoint (2026-10-15)

The background implementation supplied Rust/FRB contact and avatar codecs,
CONFIG host extraction, a secure per-account contact snapshot, an explicit
refresh card on the Flutter myTeamSpeak screen, in-memory avatar loading and a
public versions check. Chat passwords are discarded in Rust: only the declared
host crosses this new CONFIG boundary. This delivery does not implement Matrix
login, messaging, presence publication or automatic contact import at onboarding.
The initial implementation only attempts avatars for the first eight nonempty
contact IDs per refresh; persisted rosters do not persist image bytes or signed
URLs. These limits must be made explicit in acceptance rather than described
as complete desktop parity.

Parent review found two protocol problems **before installation**:

- `getContactList` must frame `AuthenticatedUser{session=1}` **directly**. An
  extra wrapper around this message corrupts the session field. A test checking
  just the RPC method and a synthetic response cannot detect that error: add an
  independent exact request-wire golden, including the session field.
- Avatar Base32 decoding must accept ASCII lowercase/mixed case as well as
  uppercase, just as the desktop explicitly uppercases the localpart. Keep
  canonical padding and zero trailing-bit checks.

Corrections, focused regression tests and a rebuilt host FRB library/APK were
requested. Earlier reported passing suites/build artifacts do **not** establish
that this reviewed protocol was correct; do not install that earlier APK or
claim live contact/avatar acceptance from its synthetic tests. The corrected
offline checkpoint follows; device acceptance is still pending.

### Corrected offline build checkpoint (2026-10-15)

Both fixes are applied in `tslib-myts/src/contacts.rs`: the roster request now
frames the session directly, and avatar Base32 accepts ASCII lowercase/mixed
case without relaxing canonical padding or zero trailing-bit checks. The exact
synthetic request golden in section 4 is asserted by Rust and the Flutter
transport mock. The new Rust regression tests failed on both bugs before the
fixes. Flutter also checks that case/padding variants send identical avatar
metadata requests; its invalid-localpart fixture now contains `0`, because
`somebody` itself is valid Base32 once lowercase is accepted.

- `cargo test -p tslib-myts -p tslib-frb`: **58 + 6 tests passed**.
- `cargo clippy -p tslib-myts --all-targets -- -D warnings`: **passed**.
- Full `flutter test` using the rebuilt host FRB library: **150 tests passed**.
- `flutter analyze`: no errors/warnings; the existing info lint remains at
  `test/myts_api_test.dart:51` (`library_private_types_in_public_api`).
  `flutter analyze --no-fatal-infos` exits successfully.
- Host `cargo build -p tslib-frb` and `docker/dev.sh apk debug`: **succeeded**;
  no binding regeneration. The host build used the dev container with ALSA
  development packages installed only in that disposable container.
- New APK: `flutter/build/app/outputs/flutter-apk/app-debug.apk`, SHA-256
  `9a265be2d88fcdc75b02d1cd51cb23c036b45dff944f4282efcef94210865dd2`.
  Its hash differs from the previous APK; both packaged FRB libraries
  (`arm64-v8a`, `x86_64`) match the newly built JNI libraries byte-for-byte.

These are synthetic/offline and build checks, not live contact/avatar acceptance.
No APK was installed, no phone data was cleared and no real-account request was
made for this correction. The separately observed Matrix 503 remains unrelated.

Protocol/crypto belongs in `../ts6-lib/crates/tslib-myts`, exposed through
`tslib-frb`; Dart handles bounded transport, persistence and UI. Use synthetic
fixtures for malformed/oversized replies, explicit application errors, missing
IDs, padded Base32, avatar-state mapping, signed-URL matching/validation,
account switching, logout and interrupted operations. Test that a failed contact
refresh cannot erase local identities/bookmarks or an earlier cached roster.
Never copy real contacts, IDs, keys, avatar URLs or captures into fixtures.

An offline test/build establishes implementation behavior under those inputs;
it is not live service, phone-network, avatar-decode or historical-chat proof.
Record each completed gate separately rather than changing all features to
“verified” when one screen loads.

## 10. Static provenance and repeatability

The binary analysis above used the supplied desktop installation under
`../teamspeak`, not the older `/opt/teamspeak` build used to render the committed
schema snapshot. SHA-256 values (public executable assets, not account data):

```text
TeamSpeak
1189672c2c290997a419100b0f29f4da95d0df9d1e744b07a764eba1e8a0944f
libtschat_client_lib_export.so
fa3219fe261a394ef7167d660352f6409489e6177058b9a087e1a03ecdda89ef
html/client_ui/main.js
9d6bea2ee5333086555c36584621c1b3462a83042ce746d3229d6766a9b82c39
```

The live Python decoder loaded the extracted descriptor closure in ignored
`captures/myts/build-7eb9fdb8`. The committed schemas remain the older
round-trip-verified snapshot described in [`proto/README.md`](proto/README.md).
Do not overwrite generated `.proto` files manually or reuse static offsets
against another build. The Go function table can be recovered from the Go
`pcHeader` in `.data.rel.ro`; the offsets above are ELF virtual addresses, not
runtime addresses or C-export trampoline addresses.

The gateway containers were already running and healthy; the probes shared
`container:wstgw-gw-1` networking in a disposable `ts6droid-dev` container with
the repository mounted read-only. No host route changes, gateway restarts,
TLS interception or installation of a root CA were needed. `.env` was read
inside the process, not passed as command-line credential arguments.

Reference documentation for standard Matrix behavior:

- [Matrix Client-Server API](https://spec.matrix.org/latest/client-server-api/)
- [Presence](https://spec.matrix.org/latest/client-server-api/#presence)
- [End-to-end encryption](https://spec.matrix.org/latest/client-server-api/#end-to-end-encryption)

These explain the standard protocol; they do not replace TeamSpeak-specific
live evidence or establish compatibility of a particular Matrix SDK.
