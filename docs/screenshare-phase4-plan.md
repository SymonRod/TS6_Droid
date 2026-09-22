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

Steps 1 and 2 are integrated in `../tslib`; started/info delivery and registry
metadata were verified against a live desktop sharer on 2026-09-07.
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

Step 2 implementation:

- Refreshed the ignored `../tslib/Cargo.lock` to the published fork `298e431`;
  no path overrides are needed.
- `crates/tslib-core/src/streams.rs`: registry keyed by `(u16, String)` (owner
  client ID and stream ID), optional metadata, patch merging for started/info/
  updated, and idempotent stopped/owner removal/disconnect cleanup.
- `Client::streams()` returns a sorted snapshot; `Event::StreamsChanged`
  contains the complete snapshot and reaches the normal return/broadcast/handler
  paths. Explicit synchronous disconnect broadcasts the empty snapshot, like
  the existing disconnect event. Temporary loss also clears stale streams.
- Ten new tests cover parsed metadata lifecycle and client integration; all
  61 core tests plus the doctest pass, as does `cargo check --workspace`.
- JNI/Python exhaustive matches recognize the new event name only to keep the
  workspace compiling. Stream payloads/accessors in bindings, Kotlin, and
  WebRTC are still deferred.

Live check: `cargo run -p tslib-core --example stream-registry --
god.serod.tech:9988 Salotto 90` observed `Wayland Source` from owner 24 via
started, then requested info with the typed command. The info response added
`viewer_count=0` while preserving name, type 3, access 1, mode 1, bitrate 33920,
viewer limit 0, and audio false. No stop/restart/update or owner departure was
observed in this session; those paths are tested offline only. The diagnostic
does not join a stream or start media and does not log SDP/ICE.

Still to verify live:

- Updated/stopped notifications and owner-departure cleanup in the registry.
- Empty outbound messages on the server: the existing serializer emits
  a bare `msg` key rather than literal `msg=`. Offline tests establish presence
  and empty-value round-trip, not server acceptance.

The generated parser inherits omitted fields from the first list entry. Keep
this in mind for registry merge tests. Update access spelling beyond captured
name-only patches remains unconfirmed; both `access` and `accessibility` are
optional in the declaration.

Step 3 implementation (2026-09-07):

- `tslib-core` now sends the viewer's three commands — `Client::join_stream`,
  `leave_stream`, `send_stream_signaling` and `request_stream_info`, all typed
  (`c2s::Out*Part`), with the required empty `msg` on join and leave.
- Two new events carry the inbound half: `Event::StreamJoinResponse`
  (decision, optional message, optional SDP offer) and `Event::StreamSignaling`
  (the `json` payload, unparsed). Both broadcast like every other event.
- `tslib-jni`: `dev.tslib.Stream` carrier plus `nativeGetStreams`,
  `nativeJoinStream`, `nativeLeaveStream`, `nativeSendStreamSignaling` and
  `nativeRequestStreamInfo`. `streams_changed` now carries the snapshot as a
  `Stream[]` in its data map; the two new events carry their fields.
- App side: `Client.java` wrappers and, in `TsClient`, a `streams` StateFlow
  plus `streamJoinResponses` and `streamSignaling` SharedFlows for the WebRTC
  layer to consume. `refreshState` reads `getStreams()` alongside users and
  channels, so a snapshot survives a missed notification.
- Unknown metadata stays `null` on the Java side rather than defaulting to
  zero: a stream is announced before its details are known.
- SDP and ICE payloads are forwarded but never logged, at any layer.

Validation: 69 `tslib-core` tests (four new: offer delivery, refusal without an
offer, opaque signaling JSON, and the four commands refusing without a
connection) plus the doctest; `cargo check --workspace`; `./gradlew
assembleDebug`. No live run yet — nothing calls join from the UI until step 4.

Step 4 implementation (2026-09-07):

- `io.github.webrtc-sdk:android:137.7151.05` (namespace `org.webrtc`) is the
  WebRTC stack. Its AAR ships four ABIs, so `defaultConfig.ndk.abiFilters`
  now pins the APK to `arm64-v8a` and `x86_64`, the two `buildRustLibs`
  produces. The APK grows to ~110 MB in debug because of it.
- `bridge/StreamViewer.kt` owns the session: one stream at a time, STUN-only
  `RTCConfiguration` with the two hardcoded TeamSpeak servers (§6), unified
  plan. `join` sends `joinstreamrequest` and arms a 30 s timeout, because a
  sharer can simply never answer. On an accepted response it applies the
  `offer=` SDP, answers with `{"cmd":"answer","args":{"answer":…}}` and
  publishes the received `VideoTrack`; incoming audio tracks are enabled.
- Trickled candidates are paced through a `Channel` at one per 120 ms, so a
  gathering burst cannot trip flood protection (§9b.5). Remote candidates that
  arrive before the offer is applied are queued, not dropped.
- Signaling parsing is permissive: the server relays `json` unchecked (§9b.2),
  so a malformed payload or an unknown `cmd` is ignored rather than fatal.
- The registry closes the loop the notifications do not: when the stream
  disappears from `TsClient.streams` — stopped, or owner gone — the viewer
  tears down and reports `stream_ended`.
- `StreamEgl` is a process-wide `EglBase`: renderers come and go with the UI,
  the decoder wants a stable context.
- App side: `ServerViewModel` creates the viewer when the service binds and
  exposes `streams`, `streamViewerState`, `viewStream` and `stopViewingStream`.
  `ServerScreen` shows a screen-share action in the top bar whenever a stream
  is on offer, a picker dialog, and a full-screen `SurfaceViewRenderer`
  overlay covering the requesting/connecting/failed/playing phases.
- Failure reasons cross the boundary as codes (`refused`, `join_timeout`,
  `stream_ended`, `ice_failed`, …) and are localized in en/fr/it; a sharer's
  own refusal text is shown verbatim. SDP and ICE are still never logged.

**Verified live on 2026-09-07**, desktop sharer → phone on home Wi-Fi:
`ICE state: CHECKING` → `CONNECTED` in ~80 ms, then
`AndroidVideoDecoder: ctor name: c2.qti.av1.decoder type: AV1`, and
`SurfaceEglRenderer: Reporting frame resolution changed to 2560x1440`. So the
sharer streams **AV1**, hardware-decoded here, and the picture arrives. Frame
rate follows the content — 5 fps on a still desktop, no drops. STUN-only ICE
punched through on the first try, as §9.5 predicted.

Two bugs the first live run exposed:

- **`ACCESS_NETWORK_STATE` was missing.** WebRTC's `NetworkMonitor` asks
  `ConnectivityService` for the active network as soon as a
  `PeerConnectionFactory` is built; a denied query is a fatal `RTC_CHECK`
  (`sdk/android/src/jni/jvm.cc`, `Check failed: false`), not an exception it
  recovers from. The process aborted on the network thread. tslib never needed
  the permission, so the manifest did not carry it.
- **A share already running when the app joins was invisible.**
  `notifystreamstarted` only fires while connected, so the registry stayed
  empty even though the user carried the streaming flag, and the viewer button
  never appeared — the share had to be restarted from the desktop.
  `ServerViewModel` now asks each flagged sharer once with `requeststreaminfo`,
  and forgets it when it stops sharing.

Also validated: `./gradlew assembleDebug`, no warnings in the new files, and
the APK carries exactly the two expected ABIs.

Still open after step 4:

- Cross-channel shares, join timeout and mid-session stop have since been
  exercised live. Only the refusal path is still manual-only: the desktop
  client in private mode ignores the request instead of refusing it, so it
  needs a fake sharer sending `respondjoinstreamrequest decision=0` by hand.

**Mobile-data ICE works** (confirmed 2026-09-07): with the phone as the viewer
on mobile data, STUN-only ICE punched through and the picture arrived, as the
§9.5 probe predicted. So the CGNAT path needs no relay after all — one less
reason to want TURN.

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
5. **§9.5, TURN — answered ahead of step 4 (2026-09-07).** The risk that P2P
   is unusable from mobile did not materialise: see "The §9.5 answer" below.
   Steps 2–4 are not invalidated, so this no longer gates the work. A full
   end-to-end ICE run still belongs to step 4.

## The §9.5 answer: STUN only, but the NAT cooperates (2026-09-07)

Measured with `cargo run -p tslib-core --example ice-probe`, a dependency-free
STUN and TURN prober. It cross-compiles for the phone with the NDK linker and
runs from `adb shell`; an optional Android network handle (from `dumpsys
connectivity`) pins it to one network. It sends no credentials and no media.

```
cargo build --release --example ice-probe            # desktop
CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER=$NDK/aarch64-linux-android24-clang \
  cargo build --release --example ice-probe --target aarch64-linux-android
adb push target/aarch64-linux-android/release/ice-probe /data/local/tmp/
adb shell /data/local/tmp/ice-probe [<net_handle>]
```

**The ICE servers do not relay.** `turn.teamspeak.com` answers STUN bindings as
`Coturn-4.6.3 'Gorst'` but ignores an Allocate entirely, where a TURN server is
required to refuse an unauthenticated one with `401` plus a realm and a nonce.
`turn2.teamspeak.com` resolves but answers nothing, on 3478, 3479 or 5349.
Neither host has an AAAA record. Consistent across desktop and phone, ten runs.
So there is no relay to fall back on: **if ICE fails, it fails.**

**The mobile NAT is not symmetric, which is what saves it.** On Fastweb LTE
(`apn.fastweb.it`), with Wi-Fi off so mobile data is the default network, one
socket got the same reflexive address from three different servers, four runs
in a row — endpoint-independent mapping, the kind hole punching handles.

| Network | Reflexive address | Mapping |
| --- | --- | --- |
| Home LAN (desktop and phone) | `82.54.4.201:<source port>` | endpoint-independent, port preserved |
| Fastweb LTE | `93.35.9.234:22540…22550` | endpoint-independent, port rewritten |

Caveats worth carrying into step 4:

- Mapping was measured, not filtering. Endpoint-independent mapping is what
  rules out the fatal case; ICE still has to punch through the filter.
- One carrier on one day. Another operator, or CGNAT under load, can still be
  symmetric — and with no relay available that connection simply fails.
- The mobile internet APN was IPv4-only behind CGNAT (`10.130.127.251/29`),
  while the home network has no global IPv6 (ULA only). IPv6, which would sidestep
  NAT entirely, is not a path between these two endpoints.
- The probe reads the ICE servers from §6, not from a live session. If step 4
  sees ICE fail, re-capture what the desktop client actually offers before
  concluding the network is at fault.

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
  They reflect but do not relay, and only the first one answers at all — see
  "The §9.5 answer" below. Plan on STUN alone.

## How to test

The desktop client is the sharer, TS6 Droid the viewer, on
`god.serod.tech:9988` (`virtualserver_capability_extensions` must list
`STREAM_P2P`). `client_is_streaming` already shows in the user list, so the
screen icon appearing is the cue that a stream should be discoverable. When the
app's behaviour disagrees with a notification, re-capture with
`../tslib/examples/stream-capture` (recipe in
[screenshare-handoff.md](screenshare-handoff.md)) rather than guessing — and
remember `captures/` never goes in git.
