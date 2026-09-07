# TeamSpeak 6 screen sharing — protocol reference

> **Status:** Phase 2 complete for **P2P mode**. A real session was captured
> end to end with `../tslib/examples/stream-capture` against a live TS6 server
> (`virtualserver_capability_extensions=FILETIME,STREAM_P2P`). SFU mode is
> still unconfirmed — §9.5 and §9.6 need a server with
> `virtualserver_sfu_endpoint` configured.
> **Phase 1 date:** 2026-09-07. **Phase 2 date:** 2026-09-07.
> **Sources:** the three files listed in
> [screenshare-research-plan.md](screenshare-research-plan.md) §0 (Phase 1,
> static analysis) plus the live transcript from Phase 2 (§9a). Raw captures
> stay local to `../tslib/captures/` — they carry real IPs and account tokens
> and are not part of this repository; only redacted, structural excerpts are
> reproduced below.
> **Companion document:** the research plan holds the rationale and the roadmap;
> this document holds the schemas.

Every identifier reproduced below is **literal** unless a line explicitly says
*inferred*. Literal means the token appears verbatim in `main.js` or in the
string table of `TeamSpeak`.

---

## 0. What Phase 2 changed

The single biggest surprise: **screen-share notifications are not JSON at
all.** Every command actually observed except `notifystreamsignaling` is an
ordinary flat TS3 `key=value` command, indistinguishable in shape from
`notifycliententerview` or any other stock notification. The layering
model in §2 undersold this — `snake_case` is not just the wire *spelling*,
it is the wire *encoding*: no nested object, no JSON, one command, flat
arguments.

`notifystreamsignaling` is the one exception, and even there JSON is scoped
tightly: the whole message sits in a single parameter, `json=`, escaped like
any other TS3 string value. Its shape is `{"cmd":"<discriminator>","args":{...}}`
— `cmd` a sibling of `args`, not nested inside it. Confirmed value: `iceCandidate`.
The SDP **offer** does not travel through `streamsignaling` in P2P mode at
all — it rides as a plain `offer=` parameter directly on
`notifyrespondjoinstreamrequest` (§4.3, §9a). Full detail and evidence: §9a.

A second finding, orthogonal to screen sharing: `client_is_streaming` already
flows over the wire on `InitServer`, `ClientEnterView` and `ClientUpdated` —
`tsclientlib` logs `Unknown argument ... "client_is_streaming"` and drops just
that field, not the whole command, because those three are already
*recognized* commands. Unlike `notifystreamstarted` and friends (unrecognized
**commands**, dropped whole per §1 below), this one only needs the field added
to `ts-bookkeeping`'s argument declarations — no `tsproto`-level hook required.
This confirms it as the cheap first increment AGENTS.md already calls out.

## 1. What Phase 1 changed

Three findings materially alter the plan:

1. **The SFU is [mediasoup](https://mediasoup.org/).** The client links
   `libmediasoupclient` and drives it over an **IXWebSocket** connection
   (`ix::WebSocketMessage`). This is a public, documented protocol with a
   maintained Android client — §5.
2. **ICE servers are hardcoded after all.** The research plan states none were
   found; that is wrong. `stun:turn.teamspeak.com:3478` and
   `stun:turn2.teamspeak.com:3478` are both in the binary — §6.
3. **`Stream_Client_Leave` has no wire command of its own**, and the reason is
   now clear: leaving is expressed as `joinstreamrequest` with `is_remove` set
   — §4.3. The open question from the plan is closed.

A fourth, smaller correction: the enum the research plan labels "session UI
state" is the **capture status** enum (`captureStatus`), not a UI-only value.

---

## 2. Layering

Three distinct JSON dialects are in play. Confusing them is the easiest way to
misread the evidence, so they are kept apart throughout this document.

| Layer | Transport | Naming | Relevance to TS6 Droid |
|---|---|---|---|
| **A — TS server commands** | the existing TeamSpeak command channel | `snake_case` | **primary**; this is what `tsclientlib` must parse |
| **B — core ↔ UI bridge** | `tsclient_internal.postMessage` inside CEF | `camelCase` | a mirror of A, and our best schema evidence |
| **C — SFU signaling** | WebSocket to the SFU | mediasoup's own | needed only in `STREAM_SFU` mode |

Layer B is desktop-only plumbing that TS6 Droid will never speak. It matters
because the Vue bundle is minified but not obfuscated, so B is readable in full
— and B's field names track A's closely enough to reconstruct A.

**Where snake_case and camelCase both exist for one concept, the `snake_case`
form is the wire form.** Confirmed pairs in the binary:

| Layer A (wire) | Layer B (bridge) |
|---|---|
| `sfu_endpoint` | `sfuEndpoint` |
| `sfu_user_id` | `sfuUserId` |
| `viewer_limit` | `viewerLimit` |
| `client_id` | `clientId` |
| `session_id` | `sessionId` |
| `stream_id` | `streamId` |
| `is_remove` | `isRemove` |

`matrixData` is the sole field found only in camelCase on both sides.

---

## 3. Identifiers

Two session kinds, discriminated structurally rather than by a tag field. The
type guards in `main.js` (module `91662`) are literal:

```js
// isServer(e)  — exported as $F
e && typeof e === "object" && "scHandlerId" in e && "serverSessionId" in e

// isServerStream(e)  — exported as JS  (adds clientId)
e && typeof e === "object" && "scHandlerId" in e && "serverSessionId" in e && "clientId" in e
```

### 3.1 Server kind — our case

```jsonc
// SessionIdentifierServer  — identifies a published session
{ "scHandlerId": 0, "serverSessionId": "" }

// StreamIdentifierServer   — identifies one participant in that session
{ "scHandlerId": 0, "serverSessionId": "", "clientId": 0 }
```

`scHandlerId` is a **client-local** connection handle, not a wire value: the
desktop client is multi-server and uses it to route. On the wire the connection
is implicit, so a `tslib` parser should expect it to be absent and fill it in
itself.

`serverSessionId` is the session key — every server-side lookup in `main.js`
maps by it. `clientId` is the ordinary TS3 client id.

Normalisation, from the same module (`$0`): a server identifier missing
`clientId` is widened with `clientId: 0`.

### 3.2 Matrix kind — out of scope

```jsonc
{ "chatId": "", "roomId": "", "userId": "",
  "id": "", "otherUserId": "", "otherDeviceId": "" }
```

Signaling travels as Matrix events, whose type names are literal in the binary:
`ts.call.join.request`, `ts.call.join.response`, `ts.call.signaling`,
`ts.call.update`, `ts.call.left`, `ts.call.stop`. Listed for completeness; TS6
Droid targets the server kind only.

---

## 4. Layer A — server commands

Command and notification names are literal; the exhaustive sweep for isolated
lowercase tokens matching `stream` found **no command beyond those already
known**, which is what closes the `Stream_Client_Leave` question in §4.3.

### 4.1 Session configuration

`Stream_Config` is the object that `notifystreaminfo` carries and that
`notifystreamupdated` amends. Its field list is exact — `main.js` assigns every
member explicitly in `updateStreamInfo`, so this is a complete enumeration
rather than a sample:

```jsonc
{
  "streamIdentifier": { /* §3 */ },
  "name":            "",     // window/screen/camera title
  "type":            3,      // source type — §7
  "mode":            1,      // transport mode — §7
  "access":          1,      // accessibility — §7
  "bitrate":         750000, // bits/s; 750000 is the client default
  "viewerLimit":     0,      // 0 = unlimited
  "audio":           true,   // stream carries audio
  "sfuEndpoint":     "",     // populated only when mode == SFU
  "sfuUserId":       "",
  "publicSessionId": "",
  "matrixData":      null    // Matrix sessions only
}
```

Wire form: `viewer_limit`, `sfu_endpoint`, `sfu_user_id` per §2.

### 4.2 Client → server

| Command | C++ payload | Body (inferred from Layer B) |
|---|---|---|
| `setupstream` | `Publish_Session` | `Stream_Config` minus the SFU fields, plus `sessionIdentifier` |
| `updatestream` | `Update_Session_Command` | partial `Stream_Config` + `session_id` |
| `stopstream` | `Stop_Stream` | `session_id` |
| `joinstreamrequest` | `Join_Stream_Request` | `stream_identifier`, `msg`, `is_remove`, `ui_state`, `config` |
| `respondjoinstreamrequest` | `Join_Stream_Response` | `session_id`, `stream_identifier`, `decision`, `send_to_peer` |
| `removeclientfromstream` | `Stream_Client_Kick` | `session_id`, `stream_identifier`, `reason` |
| `streamsignaling` | `Stream_Signaling` | §4.4 |
| `requeststreaminfo` | — | `stream_identifier` |
| `requestsfuaccessinfo` | — | — |

The command ↔ payload column is carried over from the research plan and remains
**inferred from name correspondence**. The body column is inferred by projecting
Layer B through the naming rule in §2 — it is the weakest evidence in this
document and is exactly what Phase 2 exists to confirm.

The Layer B calls these project from are literal:

```js
{cmd:"publishSession", payload:{name, type, bitrate, access, mode, viewerLimit,
                                audio, id, sessionIdentifier:{scHandlerId, serverSessionId}}}
{cmd:"joinStreamRequest", payload:{streamIdentifier, msg, isRemove, uiState, config}}
{cmd:"joinStreamResponse", payload:{id, streamIdentifier, decision, sendToPeer}}
{cmd:"removeFromSession", payload:{id, streamIdentifier, reason}}
{cmd:"updateSession", payload:{...changes, id}}
{cmd:"closeSession", payload:{id}}
{cmd:"pauseSession", payload:{id, isPaused}}
{cmd:"addBan" | "removeBan", payload:{id, ban}}
```

### 4.3 Server → client

| Notification | C++ payload | Payload shape |
|---|---|---|
| `notifystreamstarted` | `Stream_Started` | `Stream_Config` (§4.1) |
| `notifystreamstopped` | `Stream_Stopped` | `StreamIdentifierServer` alone |
| `notifystreamupdated` | `Updated_Session_Notify` | partial `Stream_Config` |
| `notifystreaminfo` | `Stream_Info` | `{ info: [Stream_Config], clientIds: [int]｜null }` |
| `notifystreamattendees` | `Stream_Attendees` | viewer list |
| `notifystreamsignaling` | `Stream_Signaling_Parsed` | §4.4 |
| `notifystreamclientjoined` | `Stream_Client_Joined` | `StreamIdentifierServer` |
| `notifystreamclientleft` | `Stream_Client_Left` | `StreamIdentifierServer` + `reason` |
| `notifyjoinstreamrequest` | `Join_Stream_Request` | forwarded verbatim |
| `notifyrespondjoinstreamrequest` | `Join_Stream_Response` | forwarded verbatim |
| `notifysfuaccessinfo` | `SFU_Access_Info_Response` | `sfu_endpoint`, `sfu_token`, `sfu_user`, `sfu_user_id` |

`notifystreamstopped` carrying only an identifier is **literal**, not inferred —
its handler destructures exactly two fields:

```js
OnStreamStopped(e) {
  let t = this._clients.get(e.clientId)?.removeSession(e.serverSessionId);
  ...
}
```

`notifystreaminfo`'s two-field envelope is equally literal, from
`OnStreamInfoReplace(e)`: it iterates `e.info` and pre-seeds a map from
`e.clientIds`, where `clientIds` may be null.

**On `Stream_Client_Leave`.** It is a member of the outbound payload variant but
has no wire command, and the exhaustive token sweep confirms none exists. The
client-side leave path in `main.js` resolves it:

```js
// leaving a stream you are viewing
tsclient_internal.postMessage({cmd:"joinStreamRequest", payload:{
    streamIdentifier: ..., msg:"", isRemove:true, uiState:{...}, config:...}})
```

So **leaving reuses `joinstreamrequest` with `is_remove` set** — a join request
with the sign flipped — rather than getting a command of its own. The
`Stream_Client_Leave` payload type is the parsed form of that same command. A
kick is the separate `removeclientfromstream`, and the binary's `is_kick` flag
distinguishes the two in the resulting `notifystreamclientleft`.

### 4.4 Signaling messages

`Stream_Signaling_Commands_Base` has four subtypes, literal from the log strings
in `StreamBase::OnStreamSignalingMessage`:

| Subtype | Purpose |
|---|---|
| `kOffer` | SDP offer — carries an `is_reconnect` flag |
| `kAnswer` | SDP answer |
| `kICECandidate` | trickled ICE candidate |
| `kReconnect` | renegotiation request |

Matching wire tokens present in the string table: `offer`, `answer`,
`iceCandidate`, `reconnect`, `sdp`, `mid`. The discriminator field name is
**not** determined — `type` and `subtype` both appear, but neither can be tied
to this structure from strings alone. Phase 2 settles it.

---

## 5. Layer C — the SFU is mediasoup

The decisive Phase 1 finding. `com::teamspeak::video::StreamSFU` links
`mediasoupclient::Transport`, `mediasoupclient::SendTransport` and a `Device`,
and exchanges `ix::WebSocketMessage` frames. Endpoints are `ws://`-schemed.

Request/notification types, literal from the `sfu_proto` namespace:

```
SFU_Protocol_Join_Request                     SFU_Protocol_Join_Response
SFU_Protocol_Set_Paused_Request               SFU_Protocol_Close_Stream_Request
SFU_Protocol_Close_Consumer_Producer_Request  SFU_Protocol_Update_Codec_Support_Request
SFU_Protocol_Main_Producer_Changed_Notification
```

Wire method names, literal isolated tokens:

```
create-stream   consume-stream   close-stream   camera-stream
join-request    join-response
transport-connect               transport-produce
```

mediasoup's own vocabulary is present in full — `rtpCapabilities`,
`routerCapabilities`, `rtpParameters`, `dtlsParameters`, `iceParameters`,
`iceCandidates`, `sctpParameters`, `producerId`, `kind` — confirming this is
stock mediasoup rather than a lookalike.

Client-side flow, reconstructed from the log strings in call order:

1. `requestsfuaccessinfo` over the TS channel → `notifysfuaccessinfo` returns
   `sfu_endpoint`, `sfu_token`, `sfu_user`, `sfu_user_id`.
2. Open the WebSocket (`SFU socket: open`).
3. `create-stream` → `StreamSFU: CreateStream success, id: …`.
4. Load the mediasoup `Device` with the router's capabilities
   (`StreamSFU: Loading Device with router capabilities: …`).
5. `transport-connect`, then `transport-produce` to publish, or
   `consume-stream` to view.
6. Codec renegotiation is explicit — `TrySwitchVideoCodec`,
   `Update_Codec_Support_Request`, and the diagnostic
   `No common codecs with SFU for consuming, waiting for remote side to publish
   a compatible codec.`

**Why this matters for Phase 4.** mediasoup publishes
[libmediasoupclient](https://github.com/versatica/libmediasoupclient) with
Android support, and the client protocol is documented. If the payloads are
stock — which Phase 2 will show — the viewer becomes an integration exercise
rather than a reverse-engineering one. Note that the plan's Phase 4 step 2
("do not port the WebRTC logic into Rust") holds even more firmly here: the
mediasoup client belongs on the Kotlin side, next to `org.webrtc`.

---

## 6. ICE configuration

Hardcoded in the binary, contradicting the research plan's §4:

```
stun:turn.teamspeak.com:3478
stun:turn2.teamspeak.com:3478
```

Both are advertised with the `stun:` scheme. The hostnames say `turn`, and the
port is the standard STUN/TURN port, so these hosts plausibly also serve TURN —
but **no `turn:` or `turns:` URL appears in the binary**, and no credentials
were found. Whether relaying is available in P2P mode behind symmetric NAT is
therefore still open, and matters: it decides whether a P2P-only server is
usable from a mobile network at all. Phase 2 or 3 should answer it.

---

## 7. Enumerations

All literal, from the enum block in `main.js`. Unchanged from the research
plan except where noted.

```js
// ScreenshareSessionStatus — ordered; comparisons rely on the ordering
ENDED = -2, FAILED = -1, NEW = 0, WAITING_FOR_RESPONSE = 1,
DISCONNECTED = 2, CONNECTING = 3, CONNECTED = 4

// source type
NONE = 0, CAMERA = 1, SCREEN = 2, WINDOW = 3, EXISTING_SESSION = 4

// ScreenshareAccessibility
NONE = 0, PUBLIC = 1, CONTACTS_ONLY = 2, PRIVATE = 3

// transport mode
NONE = 0, P2P = 1, SFU = 2

// ScreenshareLeaveReason
NONE = 0, LEFT = 1, DENIED = 2, FAILED = 3, KICKED = 4, BANNED = 5

// capture status  ← the plan calls this "session UI state"; it is captureStatus
FAILED = -1, NEW = 0, MINIMIZED_PAUSED = 1, MINIMIZED = 2, PAUSED = 3, RUNNING = 4

// session kind
SERVER = 0, MATRIX = 1

// special source identifiers (strings, not numbers)
INVALID = "-2", UPDATE = "-3"
```

Two ordering rules the client actually depends on, worth mirroring in any
reimplementation:

- `status <= NEW` means joinable; `status > NEW` means joining or joined.
- `isJoined` is `status > WAITING_FOR_RESPONSE`.

Note that `NONE = 0` for accessibility and mode is a sentinel, not a value the
server sends for a live session.

---

## 8. Session state machine

Viewer side, from the `handlers` map and the status transitions in `main.js`:

```
                   joinstreamrequest (is_remove=false)
   NEW ──────────────────────────────────────────► WAITING_FOR_RESPONSE
    ▲                                                    │
    │                             notifyrespondjoinstreamrequest
    │                                       ┌────────────┴────────────┐
    │                            decision=true                 decision=false
    │                                       ▼                         ▼
    │                                  CONNECTING ─── signaling ─► CONNECTED
    │                                       │                         │
    │  reason == LEFT                       │ failure                 │ notifystreamstopped
    └───────────────────────────────────────┴─────────────┐           │  / kick / ban
                                                          ▼           ▼
                                                       FAILED       ENDED
                     (reason > LEFT, i.e. DENIED | FAILED | KICKED | BANNED)
```

The `FAILED` vs `NEW` split on close is literal:

```js
onClose(e) {
  this.id = -1; this.idData = null; this._lastCloseReason = e.reason;
  e.reason > LEFT ? this.status = FAILED : this.status = NEW;
}
```

So a clean `LEFT` returns the session to `NEW` (rejoinable) while any other
reason parks it in `FAILED` with `reason` driving the error message. A viewer
implementation should reproduce this: it is the difference between offering
"rejoin" and showing "you were banned".

### 8.1 Per-session events

The core pushes these to a session; the map is literal:

```js
handlers = {
  update:             onUpdate,        // {status?, config?, paused?, audioSupported?, uiState?}
  joinStreamRequest:  onJoinStreamRequest,
  streamClientJoined: onViewerJoined,
  streamClientLeft:   onViewerLeft,
  closeSession:       onClose,         // {reason}
  streamCaptureError: onCaptureError,
  streamPublished:    onPublished,
  streamStatsReport:  onStatsReport,
  streamBanAdded:     onBanAdded,
  streamBanRemoved:   onBanRemoved,
}
```

`update` is partial throughout — every field is guarded with
`void 0 !== e.field` before being applied. Any reimplementation should be
equally tolerant, which also satisfies the research plan's "write permissive
parsers" constraint.

---

## 9. What Phase 1 could not determine

Static analysis has been taken as far as it goes. These were the open
questions Phase 2 had to answer; status after the capture in §9a:

1. **How the JSON body attaches to a TS3 command.** ✅ **Resolved — the premise
   was wrong.** There is no JSON body for most commands; see §0 and §9a.1.
2. **The signaling discriminator field.** ✅ **Resolved for P2P.** It's `cmd`,
   a sibling of `args`. See §9a.2.
3. **Exact wire spelling of every field.** ✅ **Resolved for every command this
   session exercised** (§9a.3). Still open for `setupstream`, `updatestream`,
   `stopstream`, `removeclientfromstream`, and anything SFU-only
   (`requestsfuaccessinfo`) — none were exercised.
4. **`notifystreamattendees` shape.** ❌ **Still open** — not triggered in the
   captured session (no command sends a viewer-list request on its own; the
   trigger is undetermined).
5. **Whether TURN relaying is available.** ❌ **Still open** — needs a client
   behind symmetric NAT, or a Phase 3 packet capture of the actual relay.
6. **Whether the SFU payloads are stock mediasoup.** ❌ **Still open** — needs
   a server with `virtualserver_sfu_endpoint` configured; the captured server
   was P2P-only (`virtualserver_capability_extensions=FILETIME,STREAM_P2P`).

## 9a. Phase 2 evidence

Captured 2026-09-07 against a live TS6 server (P2P mode only), using
`../tslib/examples/stream-capture`. One client shared a window twice
(`type=3`, a Wayland window source) and a second client joined as a viewer.
Values below are redacted/replaced with placeholders where the original
carried a real IP address, UUID or account token — the structure is
otherwise verbatim from the transcript.

### 9a.1 The JSON question, resolved

Every screen-share notification **except `notifystreamsignaling`** is a flat
TS3 command — same shape as any other notify, no envelope:

```
notifystreamstarted clid=1 id=<uuid> name=Wayland\sSource type=3 access=1 mode=1 bitrate=33920 viewer_limit=0 audio=0
notifystreaminfo clid=1 id=<uuid> name=Wayland\sSource type=3 accessibility=1 mode=1 viewer=1 bitrate=33920 viewer_limit=0 audio=0
notifystreamclientjoined clid=10 id=<uuid>
notifystreamstopped clid=1 id=<uuid> reason=1
```

Two things the JS-derived schema in §4.1 got wrong:

- **`id` is a flat UUID** (`f2f7de30-8488-...`), not the structured
  `streamIdentifier` object (`{scHandlerId, serverSessionId, clientId}`).
  That structure is Layer B (client-local) bookkeeping only; the wire
  identifies a stream by `clid` + this one UUID field, nothing else.
- **`notifystreaminfo` is not the `{info: [...], clientIds: [...]}` envelope**
  the bridge code implied. It is one flat command per stream, structurally
  close to (but not identical to — see next point) `notifystreamstarted`.

A **real inconsistency**, not a transcription error: `notifystreamstarted`
names the accessibility field `access`; `notifystreaminfo` names the same
concept `accessibility`. `notifystreaminfo` also adds a `viewer` field (a
live viewer count) that `notifystreamstarted` doesn't carry. Any parser must
treat these as two distinct field sets, not one `Stream_Config` reused
verbatim.

`joinstreamrequest` (client → server) is flat too, and `msg` is a **required**
parameter even when empty — omitting it produces `error id=1542 msg=missing
required parameter` with no indication of which field is missing:

```
joinstreamrequest id=<uuid> clid=1 is_remove=0 msg=
```

The response confirms the JSON-free pattern extends to the SDP offer itself —
it is **not** delivered via `notifystreamsignaling` at all, but as a plain,
TS3-escaped parameter on the join response:

```
notifyrespondjoinstreamrequest clid=1 id=<uuid> msg decision=1 offer=v=0\r\no=-\s...(full SDP, \r\n escaped as \s)...
```

So of the six commands actually exercised, only one — `notifystreamsignaling`
— carries JSON. Whether `setupstream`/`updatestream` (session creation and
edits, never exercised) also stay flat, or whether the fuller `Stream_Config`
shape from §4.1 needs JSON because it doesn't fit flat parameters, is still
open.

### 9a.2 The signaling discriminator, resolved

`notifystreamsignaling` is flat at the top level, with the WebRTC payload
packed into one parameter, `json=`:

```
notifystreamsignaling clid=1 id=<uuid> json={"args":{"mLine":0,"mid":"0","sdp":"candidate:...typ\shost..."},"cmd":"iceCandidate"}
```

`cmd` is the discriminator — a sibling of `args`, confirmed value
`"iceCandidate"` (matches the literal string-table token from Phase 1, not
the C++ enum name `kICECandidate`). `args` for an ICE candidate is
`{mLine: int, mid: string, sdp: string}` — `mLine`/`mid` are the WebRTC
`sdpMLineIndex`/`sdpMid`, and `sdp` here is the candidate line itself
(`candidate:... typ host ...`), not the full session description, despite the
name being shared with the outer SDP concept.

`offer`, `answer` and `reconnect` values were **not** observed — the offer
took the separate path above, and this session never reached a renegotiation.
Whether those three values exist under `cmd` here, or whether `answer` also
rides on some other command the way `offer` does, is still open.

### 9a.3 Confirmed wire spellings

| Command | Direction | Confirmed fields |
|---|---|---|
| `notifystreamstarted` | S→C | `clid`, `id`, `name`, `type`, `access`, `mode`, `bitrate`, `viewer_limit`, `audio` |
| `notifystreaminfo` | S→C | `clid`, `id`, `name`, `type`, `accessibility`, `mode`, `viewer`, `bitrate`, `viewer_limit`, `audio` |
| `notifystreamclientjoined` | S→C | `clid`, `id` |
| `notifystreamstopped` | S→C | `clid`, `id`, `reason` |
| `joinstreamrequest` | C→S | `id`, `clid`, `is_remove`, `msg` (required, may be empty) |
| `notifyrespondjoinstreamrequest` | S→C | `clid`, `id`, `msg`, `decision`, `offer` (raw SDP, not JSON) |
| `notifystreamsignaling` | S→C | `clid`, `id`, `json` (`{cmd, args}}`, §9a.2) |

`requeststreaminfo` (C→S) was exercised bare — `id=<uuid> clid=1`, no other
required fields observed. `notifystreamclientleft` was **not** observed even
though a viewer disconnected mid-session (a full server disconnect, not an
`is_remove` leave) — whether it fires only for the explicit leave/kick path
is unconfirmed.

Also confirmed, from the handshake log rather than the listener:
`virtualserver_capability_extensions` is a literal comma-separated list —
this server sent `FILETIME,STREAM_P2P`.

---

## 10. Immediate consequences for TS6 Droid

Still **no application code**, per the research plan. Two things are now firmer:

- **`client_is_streaming` / `client_streaming` remains the cheapest first
  increment**, and Phase 1 changes nothing about it: it is an ordinary TS3
  client property, needs none of the above, and lets the UI mark who is sharing.
- **Phase 4's shape is clearer.** With mediasoup on the media plane, the Android
  side is `libmediasoupclient` plus `org.webrtc`, not a hand-rolled
  `PeerConnection` driver — at least in `STREAM_SFU` mode. P2P mode still needs
  the manual path, and is the harder of the two because of §6.

**Next step:** Phase 2 — the instrumented `tsclientlib` client, logging every
unknown command, connected to a real TS6 server while a desktop client shares.
Its checklist is §9; its working plan, including the hook points in
`tsclientlib` and the build plumbing, is
[screenshare-phase2-plan.md](screenshare-phase2-plan.md).
