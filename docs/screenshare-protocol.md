# TeamSpeak 6 screen sharing — protocol reference

> **Status:** Phase 2 complete for **P2P mode**, in both roles — viewer
> (session 1, §9a) and broadcaster (session 2, §9b). Both were captured with
> `../tslib/examples/stream-capture` against a live TS6 server
> (`virtualserver_capability_extensions=FILETIME,STREAM_P2P`). SFU mode
> **cannot** be confirmed for now: TeamSpeak has not released the SFU, and
> `virtualserver_sfu_endpoint` does nothing on a self-hosted server (§9.6).
> **Phase 1 date:** 2026-09-07. **Phase 2 dates:** 2026-09-07 (sessions 1 and 2).
> **Sources:** the three files listed in
> [screenshare-research-plan.md](screenshare-research-plan.md) §0 (Phase 1,
> static analysis) plus the live transcripts from Phase 2 (§9a, §9b). Raw captures
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

| Command | C++ payload | Wire parameters — **required** / *optional* |
|---|---|---|
| `setupstream` | `Publish_Session` | **`accessibility`**, *`name`*, *`type`*, *`mode`*, *`bitrate`*, *`viewer_limit`*, *`audio`* — §9b.1 |
| `updatestream` | `Update_Session_Command` | **`id`** + any subset of the `setupstream` fields — §9b.3 |
| `stopstream` | `Stop_Stream` | **`id`**, **`reason`** — §9b.3 |
| `joinstreamrequest` | `Join_Stream_Request` | **`id`**, **`clid`**, **`is_remove`**, **`msg`** — §9a.3 |
| `respondjoinstreamrequest` | `Join_Stream_Response` | **`clid`**, **`id`**, **`decision`**, **`msg`**, **`offer`** — §9b.2 |
| `removeclientfromstream` | `Stream_Client_Kick` | **`clid`**, **`id`**, **`reason`** — §9b.3 |
| `streamsignaling` | `Stream_Signaling` | **`clid`**, **`id`**, **`json`** — §9b.2, §4.4 |
| `requeststreaminfo` | — | **`clid`**, *`id`* — §9b.3 |
| `requestsfuaccessinfo` | — | unknown — never exercised (no SFU server exists, §9.6) |

The command ↔ payload column is carried over from the research plan and remains
**inferred from name correspondence**. The parameter column is now **literal**
for every command except `requestsfuaccessinfo`: each one was sent for real and
minimised against the server's `error id=1542 missing required parameter`
(§9b). Note that this is the *server's* required set, not necessarily what a
peer client needs to function.

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
| `notifystreaminfo` | `Stream_Info` | flat, and a **`\|`-separated list** with one entry per stream of the queried client — §9b.3. (The `{info, clientIds}` envelope below is Layer B only.) |
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

| Subtype | Wire `cmd` | Purpose | `args` |
|---|---|---|---|
| `kOffer` | — | SDP offer — carries an `is_reconnect` flag | never seen here: in P2P the offer rides on `notifyrespondjoinstreamrequest` as a plain `offer=` parameter (§9a.1) |
| `kAnswer` | `answer` | SDP answer | `{"answer": "<sdp>"}` — literal, §9b.2 |
| `kICECandidate` | `iceCandidate` | trickled ICE candidate | `{"mLine": int, "mid": "…", "sdp": "candidate:…"}` — literal, §9a.2 |
| `kReconnect` | `reconnect`? | renegotiation request | not observed |

The discriminator is **`cmd`**, a sibling of `args` inside the `json=`
parameter (§9a.2). Note that the `args` key is named after the command —
`answer` for an answer — rather than a uniform `sdp`. `reconnect` remains a
string-table token only; no session reached a renegotiation.

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
3. **Exact wire spelling of every field.** ✅ **Resolved for every command
   except `requestsfuaccessinfo`.** Session 1 covered the viewer side (§9a.3);
   session 2 exercised `setupstream`, `updatestream`, `stopstream`,
   `respondjoinstreamrequest`, `removeclientfromstream`, `streamsignaling` and
   `requeststreaminfo` from the broadcaster side (§9b).
4. **`notifystreamattendees` shape.** ❌ **Still open, and now probably
   SFU-only.** Session 2 ran the full broadcaster path — publish, two viewers
   joining, a kick, a leave, an info request — and it never fired. No command
   in the (exhaustive, §4) token list requests a viewer list, and `main.js`
   contains no handler for it: `streamAttendees` exists only inside the core
   binary. See §9b.4.
5. **Whether TURN relaying is available.** ❌ **Still open** — needs a client
   behind symmetric NAT, or a Phase 3 packet capture of the actual relay.
6. **Whether the SFU payloads are stock mediasoup.** ⛔ **Blocked upstream, not
   just open.** `virtualserver_sfu_endpoint` is inert on self-hosted servers:
   TeamSpeak states the setting "does not do anything on the server side" and
   that the SFU "was not released to public yet" (TeamSpeak Community thread
   [62715](https://community.teamspeak.com/t/since-when-is-the-sfu-video-feature-in-teamspeak-6-which-self-hosted-sfu-do-you-use/62715),
   dev reply, checked 2026-09-07). There is no SFU binary to install and no
   setup documentation, so no capture can close this until TeamSpeak ships it.

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

## 9b. Phase 2b evidence — the broadcaster side

Captured 2026-09-07 against the same P2P server, transcript
`../tslib/captures/session-2.jsonl` (local only, same sensitivity caveat as
session 1). Where session 1 watched someone else share, session 2 **published
streams from the capture client itself** and drove every remaining client →
server command by hand. Method: send the command with a `return_code=<tag>`,
read the tagged reply, minimise against `error id=1542`. `return_code` is
echoed on both the `error` line **and** the notification that answers the
request, which is what makes the correlation reliable.

The two published streams carried no video — the capture tool has no WebRTC
stack — so the peers that tried to join them saw nothing. They were removed
with `stopstream` at the end of the session.

### 9b.1 `setupstream`, and the `access` / `accessibility` split

The required parameter is **`accessibility`**. `access` — the spelling
`notifystreamstarted` itself uses — is accepted but does **not** satisfy the
requirement, so a command carrying only `access` fails with `error id=1542`
while everything else about it is valid. This is the same inconsistency §9a.1
found on the receive side, and it is worse than cosmetic: the two spellings are
not interchangeable, and only one of them is required.

```
setupstream name=Test type=2 mode=1 bitrate=750000 viewer_limit=0 audio=0 accessibility=1
  → notifystreamstarted clid=13 id=<uuid-B> name=Test type=2 access=1 mode=1 bitrate=29104 viewer_limit=0 audio=0 return_code=…
  → notifyclientupdated clid=13 client_is_streaming=1
  → error id=0 msg=ok
```

Everything but `accessibility` is optional — a bare `setupstream` with only
that field is accepted. Two things the server overrides:

- **The stream `id` is server-assigned.** A client-supplied `id=<uuid>` is
  ignored: the `notifystreamstarted` that comes back carries a different UUID,
  and that is the one every later command must use.
- **`bitrate` is server-decided too.** 750000 was requested, 29104 came back —
  the same 29104 for both streams, and the pre-existing desktop share was
  reporting 33920. So the field is a live/negotiated figure, not the client's
  ask.

`client_is_streaming` flips to `1` on the first stream and back to `0` only
when the **last** one stops — with two streams open, stopping the first
produced no `notifyclientupdated` at all.

### 9b.2 The join handshake seen from the sharer, and `answer`

A viewer's request arrives as a flat notify, `msg` present but valueless:

```
notifyjoinstreamrequest clid=2 id=<uuid> msg is_remove=0
```

`respondjoinstreamrequest` requires **all five** of `clid`, `id`, `decision`,
`msg` and `offer` — the server rejects an accept that omits the SDP, so
`decision=1` and an offer are inseparable on the wire. Sending it produced:

```
respondjoinstreamrequest clid=2 id=<uuid> decision=1 msg= offer=v=0\r\no=-\s…
  → notifystreamclientjoined clid=2 id=<uuid>
  → error id=0 msg=ok
  → notifystreamsignaling clid=2 id=<uuid> json={"args":{"answer":""},"cmd":"answer"}
```

That last line is the second confirmed `cmd` value after `iceCandidate`, and it
settles the shape §9a.2 left open: **`args` for an answer is `{"answer": …}`,
keyed by the command name, not by `sdp`**. The value is empty here only because
the offer was a hand-written stub the peer's WebRTC stack could not answer —
the peer still replied, which is itself the useful part.

`streamsignaling` (C2S) requires `clid`, `id` and `json`, all three, and the
**server does not inspect the JSON**: `json={"cmd":"bogusCommand","args":{"foo":1}}`
was accepted with `error id=0 msg=ok` exactly like a well-formed candidate. The
server is a pure relay for this parameter; all validation is peer-side. Good
news for a permissive parser, and it means an unknown future `cmd` value will
reach the app rather than being filtered out en route.

### 9b.3 Update, stop, kick, info

```
updatestream id=<uuid> name=Renamed
  → notifystreamupdated clid=13 id=<uuid> name=Renamed return_code=…
```

`updatestream` takes `id` plus **any subset** of the `setupstream` fields, and
the resulting `notifystreamupdated` carries **only the fields that changed** —
so it is a patch, not a full `Stream_Config`. A parser must merge it into the
stream it already knows, never replace.

```
stopstream id=<uuid> reason=1                    → error id=0 msg=ok
removeclientfromstream clid=2 id=<uuid> reason=4 → notifystreamclientleft clid=2 id=<uuid> reason=4
joinstreamrequest id=<uuid> clid=12 is_remove=1 msg=
                                                 → notifystreamclientleft clid=13 id=<uuid> reason=1
```

`reason` is required on both `stopstream` and `removeclientfromstream`. The
values match `ScreenshareLeaveReason` (§7) as observed: **`1` = LEFT** on the
`is_remove=1` path, **`4` = KICKED** on the kick path — which also closes
§9a.3's open question about `notifystreamclientleft`: it fires on the explicit
leave and kick paths, and (per session 1) not on a plain disconnect.

`requeststreaminfo` is keyed by **`clid`**, not by stream: `id` is optional and
ignored when present. The reply is one `notifystreaminfo` **pipe-separated
list** with an entry per stream that client owns:

```
requeststreaminfo clid=13
  → notifystreaminfo return_code=… clid=13 id=<uuid-A> name=Renamed type=2 accessibility=1 mode=1 viewer=1 bitrate=29104 viewer_limit=0 audio=0|clid=13 id=<uuid-B> name=Test …
```

Two consequences for `tslib`: `notifystreaminfo` must be parsed as a
**multi-entry** command (the TS3 `|` list form), and it uses `accessibility`,
not `access`, in every entry.

### 9b.4 `notifystreamattendees` — absent from both roles

Never observed, in either session. Session 2 covered the whole broadcaster
lifecycle (publish, two distinct clients requesting to join, one accepted, one
kicked, an explicit leave, repeated info requests, stop) and it never appeared.
Combined with three static facts — no command in §4's exhaustive token sweep
requests a viewer list, `main.js` has no handler for it, and `streamAttendees`
appears only inside the core binary — the working conclusion is that it belongs
to the SFU path, where the viewer list comes from the SFU rather than from the
peer connections. It cannot be tested until TeamSpeak releases the SFU (§9.6).

### 9b.5 Two operational details worth knowing

- **Error 5635 `Stream does not exist`** — the reply to any stream command
  naming a UUID the server has forgotten. Distinct from 1542.
- **Flood protection applies to these commands.** Ten `setupstream` probes sent
  back to back tripped `error id=524 client is flooding extra_msg=retry in
  9985ms`, with the retry delay growing 5 s per further offence. Probing needs
  roughly one command every 4 s; a real client is nowhere near this, but a
  reconnect storm or a candidate burst could be.

---

## 10. Immediate consequences for TS6 Droid

Still **no application code**, per the research plan. Three things are now firmer:

- **`client_is_streaming` / `client_streaming` remains the cheapest first
  increment**, and Phase 1 changes nothing about it: it is an ordinary TS3
  client property, needs none of the above, and lets the UI mark who is sharing.
- **A P2P viewer is now fully specified on the signaling side.** Every command
  a viewer needs — `joinstreamrequest` in, `notifyrespondjoinstreamrequest`
  with the offer, `streamsignaling` out for the answer and candidates,
  `notifystreamsignaling` in for theirs, `joinstreamrequest is_remove=1` to
  leave — has a confirmed wire spelling (§9a.3, §9b). Nothing in §9's remaining
  open items blocks it: §9.4 is SFU-shaped, §9.6 is blocked upstream, and §9.5
  (TURN) is a connectivity question that only shows up at run time.
- **Phase 4's shape is clearer.** With mediasoup on the media plane, the Android
  side is `libmediasoupclient` plus `org.webrtc`, not a hand-rolled
  `PeerConnection` driver — at least in `STREAM_SFU` mode. P2P mode still needs
  the manual path, and is the harder of the two because of §6 — but it is also
  the only mode that exists today (§9.6).

**Next step:** Phase 4, P2P only — `tslib-core` parses the `notifystream*`
family, `tslib-jni` forwards it, and the WebRTC work stays on the Kotlin side.
The signaling contract is §4.2/§4.3 as amended by §9a.3 and §9b; the
gating unknown that remains is §9.5, whether a mobile network can reach the
sharer without TURN.
