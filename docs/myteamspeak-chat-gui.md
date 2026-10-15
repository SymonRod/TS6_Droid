# Account chat GUI (Flutter)

**2026-10-15.** Replaces the research/test screens (receive-only history page,
contacts card, "Check chat connectivity") with a real chat interface. The Rust
engine (`../ts6-lib/crates/tslib-myts/src/history.rs`) and the protocol research
are unchanged in spirit; the test UI and its probe tests are gone. The snapshot of
the previous state is on branch `feat/chat-gui`'s first commit in both repos.

## What the user can do

Entry: the **Account chat** card at the top of the home (connection) screen
(`/chat`, also usable while connected to a server); signed out, it leads to the
myTeamSpeak sign-in. The account key is unlocked in memory from the account
password; **Lock chat** in the profile forgets the key again.

### Remembered password (opt-out)

"Remember password on this device" is **on by default** and can be switched off
at sign-in, on the chat unlock screen and on the account screen. While on, the
password is kept in `flutter_secure_storage` (Android Keystore) next to the
session (`MyTsSessionStore.kPassword`), and the chat unlocks without a prompt
(and so does the account import). The preference itself is `kRememberPassword`.
It is saved only after the password has actually worked, never for a failed
attempt. It is wiped on sign-out, when the option is turned off, and when it stops
unlocking the account (the user then sees "The saved password no longer works"
and the password form). Opting out stores nothing: the password is asked each
time, as before. Tradeoff: the stored password is the account password itself
(the KDF needs it), so anyone who can read the app's secure storage on an
unlocked, compromised device could use it; opting out is the maximum-security
choice. A biometric gate on reading it is a possible follow-up.

| Tab | Features |
|---|---|
| Chats | conversation list (avatar, last message, time, lock icon for encrypted rooms), invitations with accept/decline, pull-to-refresh, "New chat" from contacts |
| Conversation | bubbles with day headings, load older messages, copy by long-press, pending/failed sends with retry (same transaction id), presence of the peer in the header, leave conversation; **writing in clear rooms and in one-to-one encrypted rooms** (see "Encrypted sending") |
| Contacts | roster with avatars and presence, search, open chat, add / edit note / remove |
| Profile | presence (available, away, do not disturb, appear offline), status message (100 UTF-16 units), display name, own avatar display |

Polling replaces `/sync`: the open conversation every 5 s, the lists every 25 s
while the chat screen is visible. There is **no background sync or notification**.

## Behaviour decided on purpose

- **Clear rooms send in plaintext, one-to-one encrypted rooms send end to end.**
  `History::send_step` decides per room (see "Encrypted sending"). Encrypted rooms with
  no single peer (groups, or a direct room whose peer is not known yet) and rooms
  whose state was never read stay read-only, with a notice that says so.
- **New chats are unencrypted** (`createRoom`, `trusted_private_chat`, `m.direct`
  updated). The UI asks for explicit confirmation first.
- Presence uses the desktop extension (JSON inside `status_msg`, base `online` or
  `offline`), not the avatar enum. Remote presence is read with `GET presence`; a
  404 means "unknown" and no dot is drawn. Shared-server advertisement is not sent.
- Invitations come from an **initial** `/sync` with an empty filter, `timeout=0`
  and `set_presence=offline`, never with a `since` token, so to-device events are not
  acknowledged and our own presence is untouched.
- A rejected token (401) is reported, never repaired by a new login; an uncertain
  earlier login stays fenced (unchanged from the history reader).

## Not available yet

- **Changing the own avatar.** `requestUploadAvatar` only returns an error code; how
  the image bytes reach storage (native `uploadAvatar(url, states)` in the desktop)
  has not been reverse engineered. The profile shows the current picture and says so.
- Attachments, edits/reactions/replies composing, read receipts, typing, group
  creation, notifications, Matrix device management; encrypted sending in group
  rooms; receiving *new* encrypted messages without the desktop's cloud backup
  (see "Encrypted sending" for what is and is not covered).
- Contact add/edit/remove (`updateContact`/`removeContact`) follow the recovered
  schema and are covered by offline request-shape tests only: **not yet confirmed
  against a live account.** Failures surface as "Couldn't update your contacts".

## Code map

- Rust: `history.rs` actions `login whoami rooms state messages send presence_set
  presence_get profile set_name invites join leave direct create_dm set_direct`
  (all take a JSON argument object, return method + raw path segments) and the
  encrypted-send actions `keys_upload keys_query keys_claim share_keys send_encrypted`
  implemented in the child module `history/e2ee.rs`; `contacts.rs`
  `contact_update_request` / `contact_remove_request` / `parse_ack`.
- FRB: `tslib-frb/src/myts.rs` (`my_ts_history_*` including `my_ts_history_send_step`
  and `my_ts_history_send_reset`, `MyTsHistoryRequest.persist`, `my_ts_build_contact_*`).
- Dart: `lib/src/chat/` (`chat_client.dart` serialised Matrix exchange and sealed
  snapshot and the send loop, `chat_controller.dart` state/polling/consent,
  `chat_models.dart`, `avatars.dart`) and `lib/src/ui/chat/`.
- Snapshot compatibility: new state fields use `serde(default)`, so snapshots saved
  by the history reader still open (test included).

## Verification

Offline, last measured 2026-10-15: `cargo test -p tslib-myts --offline` **127 passed**
(43 in `history.rs`, 24 end-to-end in `history/tests/send_e2e.rs`, the rest in other
modules); Python `tools/myts` **73 passed** (including the 3 libolm interop tests);
Flutter **212 passed** (183 before encrypted sending was added to the app) and
`flutter analyze` reports the one known info at `test/myts_api_test.dart:51`. The
Flutter tests include an end-to-end ChatClient/controller run against an in-memory
Matrix server and widget tests of the screens; they need the host FRB library built in
the dev container (see "Commands").

On the owner's SM-S938B (debug APK, signature SHA-256 `36594e7f…ad76d`, updated with
`adb install --no-streaming -r`, `firstInstallTime` unchanged): after the login
retry below, `logcat` showed `login`, `whoami`, `rooms`, `invites`, `direct`,
`state`, `messages`, `presence_get`, `profile` all HTTP 200, repeating every ~25 s.
The debug build logs only `chat: <action> -> HTTP <status>` (never URLs, headers or
bodies); read it with `adb logcat -d | grep "flutter : chat:"`.

## Findings from the first phone run (2026-10-15)

1. **"Server rejected the saved login" was misleading.** The earlier history-reader
   build (broken HTTPS factory) had left a login intent without a token. The engine
   then refused every call with `Authentication`, which the UI worded as a rejected
   token. Fixed: `NotLoggedIn` is a separate error (`chat:not_logged_in`), the banner
   offers **Retry chat login**, backed by `History::allow_login_retry` /
   `ChatClient.retryLogin`. The retry keeps the Matrix `device_id`, so it cannot create
   a duplicate device even if the first attempt had reached the server. After it,
   everything returned 200.
2. **The owner's conversations are encrypted**, so the composer was read-only in that
   build (plaintext send only worked in rooms without `m.room.encryption`). Encrypted
   sending has since been implemented (next section) but not yet tried on that phone.
3. **Open bug: "New chat" lists long gibberish names.** Contacts have empty
   `ts_chat_identifier`, often empty `note`, and a Base32 Matrix localpart (for example
   `@MY======:host`). `contactName()` falls back to `matrix_id`. Display names exist in
   the room member state (`m.room.member.displayname`) and in `GET profile`, but the
   engine does not harvest the member names into `names`, and the picker reads the
   state once, possibly before `refreshPeople` has finished. Suggested fix: in the
   `state` action store each member `displayname` in `names` (do not overwrite a
   profile name), re-read the state when the picker is built, and never show a raw
   Base32 ID: fall back to a short neutral label.
4. Read-only status of everything else is unchanged; contact add/edit/remove is still
   unconfirmed against a live account.

## Encrypted sending (implemented; verified offline only)

**Status.** The app can send end-to-end encrypted text in **one-to-one** encrypted
rooms. It has **never run against the real TeamSpeak Matrix server or the desktop
client**. Live verification is pending and needs the owner's explicit confirmation: it
publishes a device on a real account and shares keys with that account's devices.
Do it with the disposable accounts first.

### Engine (`../ts6-lib/crates/tslib-myts/src/history/e2ee.rs`, vodozemac 0.9)

Sans-IO like the rest of `History`; every action is a `request` / `accept` pair and the
whole state lives in the sealed snapshot (new `serde(default)` fields, old snapshots
still open).

| Action | What it does |
|---|---|
| `keys_upload` | Creates the Olm account lazily. First upload: signed `device_keys` (canonical JSON, own sorted-key serializer), 50 signed `signed_curve25519` one-time keys and one signed fallback key; later: top-up below 25, or an empty upload that just returns the counts (at most once a minute). Keys are marked published only after a valid reply; a retry re-sends the same keys |
| `keys_query` | Devices of our own user and the room's single peer. Each device must self-verify, list both Olm and Megolm algorithms and match its map keys. Keys are pinned on first sight (**TOFU, no cross-signing, no "verified" flag**); other keys for a known device ID set a sticky `changed` flag and the device is never shared with. Devices missing from a reply are revoked from the cache together with their Olm session |
| `keys_claim` | One `signed_curve25519` key per device without an Olm session, signature checked against the pinned key (fallback keys accepted), outbound Olm session created. Devices that give nothing are put in a 10-minute cooldown, so the loop cannot spin |
| `share_keys` | `PUT sendToDevice/m.room.encrypted/<txn>` with `m.room_key` Olm-encrypted per device. **Numeric `chain_index` and the outer `device_id` / `session_id` are mandatory for the desktop** (chat-history §16). The body is stored as pending *before* the HTTP call, a retry returns it byte for byte, and the URL txn is `{label}_{session tag}_{counter}` so a server never drops a later, different share |
| `send_encrypted` | `PUT rooms/<room>/send/m.room.encrypted/<txn>`; the Megolm ratchet advances and the event is stored as pending *before* the request. A retry with the same txn returns the stored event (no second index); a pending event of another txn is replaced (the server de-duplicates by txn, and a burned index is harmless). The local echo is the encrypted event itself, read back through the inbound copy of our own session |
| `send_reset` (method) | Drops a stuck pending share/event of a room, after a permanent server refusal or when the user discards a failed message |

Megolm sessions rotate after the room's `rotation_period_msgs` (default 100, clamped
1..10000) or `rotation_period_ms` (default 7 days, clamped 1 h..30 d), when the room's
user set changes, or when a device that held the key is revoked or flagged `changed`.
Creating a session also stores an inbound copy in `sessions` (sender = us, strict
metadata, `empty_own: false`), so our own messages decrypt after a restart.

**Orchestrator contract.** `History::send_step(room, txn)` is a pure function of state:

```text
{"action": "keys_upload"|"keys_query"|"keys_claim"|"share_keys"|"send_encrypted"
           |"send"|"done"|"fail",
 "args":   {} | {"room"} | {"room","txn"}   // the caller adds "text" for the two sends
 "code":   "invalid"|"not_logged_in"|"room_unknown"|"unsupported_room"|"no_recipients"
           |"limit",                        // only with "fail"
 "warnings": [] | ["device_changed"]}
```

The caller loop (`ChatClient.send`) is: `send_step` → build the request → if
`Request.persist`, snapshot **before** the HTTP call → HTTP → `accept` → snapshot,
until `done` or `fail`, capped at 12 steps. `persist` is true for `login`,
`keys_upload`, `keys_claim`, `share_keys` and `send_encrypted`. Each message needs a
fresh txn; reusing the txn of a finished message sends nothing (`done`).

### App behaviour

- **Consent.** The first encrypted send publishes this phone's device (it appears as
  "TS6 Droid" in the desktop's device list, for the owner and the contact) and shares
  room keys with every device of the people in the room, verified or not. The UI asks
  once per account (dialog, Cancel keeps the typed text); `ChatClient.send` itself
  refuses every key step without the flag, so the UI cannot be bypassed. The flag lives
  in secure storage next to the snapshot (`myts_chat_e2ee_v1_<sha256(account)>`, outside
  the Rust snapshot) and is dropped when a chat is opened with no snapshot, because
  that login creates another device.
- **Errors.** `no_recipients`, `unsupported_room` and `limit` get their own messages. A
  permanent 4xx (not 401, 408, 429) on `share_keys` / `send_encrypted` triggers
  `send_reset` so the room is not stuck; network errors and 5xx keep the pending state
  for a retry. A failed message does not block the next one.
- **`device_changed`** shows a non-blocking snackbar once after the message went out
  without that device.

### Verified offline

- Rust: unit tests per action and 24 end-to-end tests (`history/tests/send_e2e.rs`) with
  a fake Matrix server and real vodozemac peers that actually receive the to-device
  event, build the Olm and Megolm sessions and decrypt (restarts at every stage, retries,
  rotation, revoked/changed devices, cooldown, caps, own-message read-back).
- libolm interop: `tools/myts/test_interop_rust_e2ee.py` plays a full send from the
  Rust engine (`examples/e2ee_interop.rs`, fake server inside it) against a **libolm**
  peer: our signatures verify with libolm, libolm decrypts the key share (numeric
  `chain_index` checked on the raw JSON) and the Megolm event, and a tampered one-time
  key produces no share.
- Flutter: the plumbing only (the fake server never decrypts). Whole chain and its
  order, second message, retries with the identical stored event also across a restart
  from the sealed snapshot, lost reply, failed-A-then-B, permanent vs transient refusal
  of a share, no recipients, a device without keys, consent (declined, accepted once,
  persisted, dropped with the snapshot), controller state, composer states, consent
  dialog and failure notices. `device_changed` is covered in Rust; in Dart only the
  plumbing is tested, through a test hook on the plan, because the real flag needs a
  second `keys/query` and the engine re-queries only after 5 minutes.

### NOT verified / known limits

- **Nothing has run against the real TeamSpeak Matrix server or the desktop client.**
  The `keys/upload`, `keys/query`, `keys/claim` and `sendToDevice` replies, and in
  particular `fallback_keys` in `keys/upload`, are untested live; they follow the Matrix
  r0 shape and chat-history §16.
- **Receiving new encrypted messages needs the desktop's cloud backup.** There is no
  `/sync` with a `to_device` cursor, so room keys other devices share with this phone
  are not read; a phone-only account will not decrypt new incoming sessions. This is
  the next delivery.
- No cloud backup publication of our own sessions; only the key shares to devices.
- Group rooms are unsupported (the engine needs one peer to know whose devices to ask).
- TOFU without verification or cross-signing, and keys go to unverified devices.
- The 512-session cap of `sessions` is shared with sessions restored from the cloud and
  there is **no eviction**: each Megolm rotation adds one, so a very busy account ends
  at `limit` ("This phone can't hold more encryption sessions").
- If the app dies after the server accepted an event but before the reply was stored,
  the retry completes under the same txn and the server returns the same event. A
  message the user *discards* in that window may still appear after the next history
  read.
- Pickles (`AccountPickle`, `SessionPickle`, `GroupSessionPickle`) are not zeroized on
  drop; they live in the sealed snapshot, which is.
- Changing a txn's text between attempts is not supported: the stored event wins.

### Commands

Rebuild the FRB bindings (rustfmt is not in the image and the unformatted output
differs by thousands of lines; the host library build also needs `libasound2-dev` and
`pkg-config`, installed in the throw-away container):

```bash
cd docker && env HOST_UID=$(id -u) HOST_GID=$(id -g) TSLIB_DIR=/home/rod/develop/ts6-lib \
  docker compose -f docker-compose.yml run --rm -T dev bash -lc \
  'rustup component add rustfmt; cd /workspace/TS6_Droid/flutter && flutter_rust_bridge_codegen generate'
```

Flutter tests (the host `flutter test` cannot load the container's package config):

```bash
TSLIB_DIR=/home/rod/develop/ts6-lib docker/dev.sh bash -lc 'cd /workspace/TS6_Droid/flutter && TSLIB_FRB_LIB=/workspace/tslib/target/debug/libtslib_frb.so TSLIB_HISTORY_FIXTURE=/workspace/tslib/crates/tslib-myts/tests/fixtures/history-libolm.json flutter test --no-pub'
TSLIB_DIR=/home/rod/develop/ts6-lib docker/dev.sh bash -lc 'cd /workspace/TS6_Droid/flutter && flutter gen-l10n && flutter analyze --no-pub'
```

Rust and libolm (from the repository root, `../ts6-lib` for cargo):

```bash
(cd ../ts6-lib && cargo test -p tslib-myts --offline && cargo clippy -p tslib-myts --all-targets --offline)
unshare -Urn captures/myts/.venv/bin/python -I -m unittest discover -s tools/myts -p 'test_*.py'
# regenerate the synthetic libolm peer used by the Flutter tests
unshare -Urn captures/myts/.venv/bin/python -I tools/myts/generate_e2ee_peer_fixture.py \
  flutter/test/fixtures/e2ee_peer.json
```

### Next steps

1. Live check with the **disposable accounts** (owner's explicit confirmation first):
   one encrypted message to a contact whose desktop client is open, confirming it shows
   there, that the new "TS6 Droid" device is listed, and that a second message reuses
   the session. Only then the owner's real account.
2. Receive new keys without the cloud: `/sync` with a persisted `since` token for
   `to_device` (Olm `m.room_key`), saved atomically with the sessions it creates, with
   `device_one_time_keys_count` driving top-ups. Do not add `since` to the existing
   `invites` action: it is deliberately an initial sync that never acknowledges
   to-device events.
3. A session eviction policy, group rooms, own-avatar upload, notifications.

Also not done: own-avatar upload (needs reverse engineering of the native
`uploadAvatar`; `requestUploadAvatar` only returns an error code), attachments,
notifications, background sync.

## Repository state

Nothing from 2026-10-15's chat GUI work is committed. The pre-GUI research state is
the first commit of branch `feat/chat-gui` in TS6_Droid and `../ts6-lib`; the GUI,
Rust actions, FRB regeneration and docs are uncommitted on top of it.

## Sign-in starts from scratch (2026-10-15)

Every myTeamSpeak sign-in now begins with a clean slate. If the phone holds any
account data, the login screen warns first (`mytsResetTitle`/`mytsResetBody`);
cancelling signs nothing in. On confirmation the sign-in is sent, and **only
after the credentials are proven correct** `LocalReset.wipe()`
(`flutter/lib/src/myts/local_reset.dart`) runs, before the new session is stored
and the import starts: a wrong password deletes nothing.

Deleted: the whole secure storage (session, saved password, account vault with
imported identities and bookmark passwords, chat device keys and caches,
encryption consent, contact cache), the saved server bookmarks plus the last
address, and the "setup done" marker. The old server-side session is deleted
best-effort. Kept: the local TeamSpeak identity file (`identity.txt`) and the
general settings. Plain sign-out is unchanged and still wipes only the session.

Consequence: this phone's chat device keys are gone, so the next encrypted chat
publishes a new device and asks for the consent again; the previous device
stays listed server-side. `MyTsSecureBackend.deleteAll()` exists only for this.
