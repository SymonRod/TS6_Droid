# TeamSpeak 6 screen sharing — protocol reference

> **Status:** Phase 1 complete (static schema extraction). No traffic captured yet.
> **Phase 1 date:** 2026-09-07
> **Sources:** the three files listed in
> [screenshare-research-plan.md](screenshare-research-plan.md) §0, re-verified by
> MD5 on this date — unchanged since the reconnaissance pass.
> **Companion document:** the research plan holds the rationale and the roadmap;
> this document holds the schemas.

Every identifier reproduced below is **literal** unless a line explicitly says
*inferred*. Literal means the token appears verbatim in `main.js` or in the
string table of `TeamSpeak`.

---

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

Static analysis has been taken as far as it goes. These are the open questions,
and each is a direct input to Phase 2:

1. **How the JSON body attaches to a TS3 command.** TS3 commands are
   `command key=value key=value`; the bodies here are JSON objects. Whether the
   JSON is one escaped parameter, and under which key, is not recoverable from
   strings. *This is the single most important unknown* — nothing can be parsed
   without it.
2. **The signaling discriminator field.** §4.4: the four subtypes are known, the
   field that carries them is not.
3. **Exact wire spelling of every field.** §2 gives the rule and seven confirmed
   pairs; the rest is projection.
4. **`notifystreamattendees` shape.** The command is literal, the payload is not
   consumed anywhere legible in `main.js`.
5. **Whether TURN relaying is available** (§6).
6. **Whether the SFU payloads are stock mediasoup** or carry TeamSpeak
   extensions (§5).

None of these blocks Phase 2 — they are its checklist. A single captured session
should close 1 through 4 at once.

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
