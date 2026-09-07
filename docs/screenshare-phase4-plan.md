# Phase 4 — the P2P viewer, implementation handoff

> Read [screenshare-handoff.md](screenshare-handoff.md) first for where the
> research stands. This document is the *build* plan: what to write, in what
> order, and which details bite. The wire schemas it refers to live in
> [screenshare-protocol.md](screenshare-protocol.md) — §9a.3 and §9b are the
> authority, §4.2/§4.3 the overview.

**Scope: viewing someone else's screen, in `STREAM_P2P` mode, on Android.**
Sharing the phone's own screen (`MediaProjection`, encoder, `setupstream`) and
`STREAM_SFU` are both out of scope — the latter is blocked upstream until
TeamSpeak ships the SFU (protocol §9.6).

## What changed since the plan was written

**We now own the declarations.** The research plan assumed `tslib` could not
see the `notifystream*` family, because `tsclientlib` drops unknown *commands*
whole — which is why `examples/stream-capture` hooks `tsproto`'s packet
listener. That was a capture-time workaround; it is not how the app should
read them.

Since `client_is_streaming` we build against
[SymonRod/tsclientlib](https://github.com/SymonRod/tsclientlib) (branch
`ts6-client-is-streaming`, declarations submodule
[SymonRod/tsdeclarations](https://github.com/SymonRod/tsdeclarations) — see
AGENTS.md). So the right move is to **declare the stream commands in
`Messages.toml`**. A declared command with no `MessagesToBook.toml` rule
arrives in `tslib-core` as `StreamItem::MessageEvent(InMessage)` and lands in
the existing `match` in `process_message_event` (`crates/tslib-core/src/client.rs`) —
the same path `ChannelListFinished` and friends already take. No book entry:
a stream is not a book object, and the book's add/update/remove machinery
would fight the fact that a client can own several streams at once.

## Implementation status (2026-09-07)

Step 1 is published and verified offline, but not tested against a live sharer.
Both forks retain the `ts6-client-is-streaming` branch: declarations `9ed2a74`,
tsclientlib `298e431` (including the updated submodule pointer). Files:

- `../tsclientlib/utils/tsproto-structs/declarations/Messages.toml`: all eight
  incoming notifications and three outgoing viewer commands, without book rules.
- `../tsclientlib/tsclientlib/src/tests.rs`: seven stream tests covering every
  notification, multi-entry info, partial updates, refusal without an offer,
  SDP/JSON escaping, and outbound join/leave/signaling/info serialization.

Validation: `cargo test --offline -p tsclientlib --lib` passed all 35 tests;
`cargo test -p ts-bookkeeping -p tsproto-structs -p tsproto-packets` passed
all eight tests. `tslib-core` and `stream-capture` also passed `cargo check`
with command-line Cargo patches pointing the four fork dependencies at the
local checkout. No persistent path dependency was added. That check updates
the untracked `../tslib/Cargo.lock`; an ordinary Cargo invocation resolves the
published dependencies again.

Before treating step 1 as integrated:

- Refresh existing `tslib` Cargo lockfiles to resolve the published fork update.
- Verify typed notification delivery against a desktop sharer. The existing
  `process_message_event` fallback logs command names, not parsed fields; no
  diagnostic arms or registry were added yet. Avoid logging raw SDP/ICE.
- Verify empty outbound messages on the server: the existing serializer emits
  a bare `msg` key rather than literal `msg=`. Offline tests establish presence
  and empty-value round-trip, not server acceptance.

The generated parser inherits omitted fields from the first list entry. Keep
this in mind for registry merge tests. Update access spelling beyond captured
name-only patches remains unconfirmed; both `access` and `accessibility` are
optional in the declaration. Next implementation increment: step 2, the stream
registry. JNI, WebRTC, Android UI, and the mobile-network ICE test remain undone.

## Order of work

Each step is a commit that builds and does something observable.

1. **Declare the viewer's commands** in the fork (`Messages.toml`, no book
   rules). Server → client: `notifystreamstarted`, `notifystreamstopped`,
   `notifystreamupdated`, `notifystreaminfo`, `notifystreamclientjoined`,
   `notifystreamclientleft`, `notifyrespondjoinstreamrequest`,
   `notifystreamsignaling`. Client → server: `joinstreamrequest`,
   `streamsignaling`, `requeststreaminfo`. Fields verbatim from §9a.3 and §9b;
   mark everything the server does not always send with `?`. Verify by logging
   the parsed struct — a capture-driven session is not needed, the desktop
   client sharing a window produces all of them.
2. **A stream registry in `tslib-core`.** `HashMap<(ClientId, StreamId), Stream>`,
   fed by started/updated/stopped/info, exposed as an `Event`. `updatestream`
   is a **patch** (§9b.3): merge, never replace. At this point the app can list
   available streams without any WebRTC at all — a good place to stop and
   verify against a real sharer.
3. **JNI surface**: the stream list plus a join/leave call, mirroring how
   channels and users already cross the boundary (`crates/tslib-jni/src/types.rs`,
   `dev.tslib.*` stay dumb data carriers).
4. **The WebRTC side, in Kotlin.** `org.webrtc` `PeerConnection` per stream:
   set the remote offer from `notifyrespondjoinstreamrequest`, answer through
   `streamsignaling`, trickle candidates both ways, render into a
   `SurfaceViewRenderer`. Keep it on the Kotlin side — Rust does signaling
   transport only.
5. **§9.5, TURN — do this early, not last.** Run the viewer on mobile data
   (symmetric NAT) against a sharer elsewhere and see whether ICE completes.
   If it does not, P2P is unusable from mobile and the whole feature waits on
   the SFU. It is a one-evening test that can invalidate steps 2–4, so run it
   as soon as step 4 produces any ICE at all — or even before, with a
   throwaway harness.

## The viewer handshake, end to end

```
(notifystreamstarted clid=<sharer> id=<uuid> …)      ← a stream exists
joinstreamrequest id=<uuid> clid=<sharer> is_remove=0 msg=      →
notifyrespondjoinstreamrequest clid=<sharer> id=<uuid> msg decision=1 offer=<SDP>   ←
streamsignaling clid=<sharer> id=<uuid> json={"cmd":"answer","args":{"answer":"<SDP>"}}  →
streamsignaling / notifystreamsignaling  json={"cmd":"iceCandidate","args":{…}}   ↔
joinstreamrequest id=<uuid> clid=<sharer> is_remove=1 msg=      →  (leave)
```

`decision=0` is a refusal; the sharer's client decides, so a join can simply
never be answered — the UI needs a pending state and a timeout.

## Details that bite

- **`msg` is required even when empty** on `joinstreamrequest`. Omitting it
  gives `error id=1542 missing required parameter`, which does *not* name the
  field (§9a.1).
- **`access` vs `accessibility`.** `notifystreamstarted` says `access`;
  `notifystreaminfo` says `accessibility` for the same concept, and adds a
  `viewer` count. Two field sets, not one (§9a.1).
- **`notifystreaminfo` is a `|`-separated list**, one entry per stream the
  queried client owns (§9b.3). Declare it as a list command and iterate.
- **The SDP arrives TS3-escaped** as a plain `offer=` parameter, `\r\n` as
  `\s` — `tsproto` unescapes it, so what reaches the struct is already a real
  SDP. Do not unescape twice.
- **`id` and `reason` collide with existing declarations.** `id` is declared as
  a `ChannelId` and `reason` as a `str`, while the stream commands use a UUID
  string and an integer enum. Use the `@` disambiguator the file already uses
  elsewhere (`map="id@stream", ts="id"`, as with `client_nickname@initserver`).
- **The server does not inspect `json`** (§9b.2) — it is a pure relay, so a
  malformed peer message reaches the app rather than being filtered. Parse
  defensively and ignore unknown `cmd` values instead of erroring.
- **`notifystreamclientleft` does not fire on a plain disconnect** — only on
  the explicit leave and kick paths (§9b.3). A viewer must also drop streams
  when the sharing client leaves the server.
- **Flood protection is real** (`error id=524`, §9b.5). A candidate burst is
  the plausible way a real client trips it; batch or pace trickled candidates.
- **ICE servers are hardcoded in the desktop client**:
  `stun:turn.teamspeak.com:3478` and `stun:turn2.teamspeak.com:3478` (§6).
  Whether they also relay (TURN, not just STUN) is exactly the §9.5 unknown.

## How to test

The desktop client is the sharer, TS6 Droid the viewer, on
`god.serod.tech:9988` (`virtualserver_capability_extensions` must list
`STREAM_P2P`). `client_is_streaming` already shows in the user list, so the
screen icon appearing is the cue that a stream should be discoverable. When the
app's behaviour disagrees with a notification, re-capture with
`../tslib/examples/stream-capture` (recipe in
[screenshare-handoff.md](screenshare-handoff.md)) rather than guessing — and
remember `captures/` never goes in git.
