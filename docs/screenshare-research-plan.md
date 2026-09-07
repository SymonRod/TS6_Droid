# TeamSpeak 6 screen sharing — reconnaissance and implementation plan

> **Status:** exploratory. No change to the app is justified yet.
> **Phase 1 is complete** — its output is
> [screenshare-protocol.md](screenshare-protocol.md), which supersedes this
> document wherever the two disagree (see the corrections noted below).
> **Recon date:** 2026-09-07
> **Method:** static analysis (`strings`, `grep`) of the installed desktop client.
> **No traffic was captured or decrypted in this phase.**

## 0. Provenance

Every piece of evidence in this document comes from three files:

| File | Size | MD5 |
|---|---|---|
| `/opt/teamspeak/TeamSpeak` | 66,365,272 B | `8234f961015da34f1387fa735a7443b0` |
| `/opt/teamspeak/libtschat_client_lib_export.so` | 20,326,736 B | `c80d95c7e850739d9de29d3d37cbf025` |
| `/opt/teamspeak/html/client_ui/main.js` | 10,080,350 B | `ab4fd33a8e1fa31561bafa11f5401ba1` |

Build dated 2025-07-13. The client is CEF-based (`libcef.so`, 251 MB); the UI is
a Vue bundle that is **minified but not obfuscated**, so identifiers are
readable. `libtschat_client_lib_export.so` is a Go library (Matrix client +
libolm) used for MyTS chat.

Extraction commands used:

```bash
strings -n 4 /opt/teamspeak/TeamSpeak | grep -axE "[a-z_]{3,40}" | grep -aE "stream|video|screenshare|sfu"
strings -n 4 /opt/teamspeak/TeamSpeak | grep -aiE "streaming|screenshare"
strings -n 8 /opt/teamspeak/libtschat_client_lib_export.so | grep -oaP 'json:"[a-zA-Z0-9_]+,?[a-z]*"'
grep -oaP ".{0,200}ScreenshareSessionStatus.{0,120}" /opt/teamspeak/html/client_ui/main.js
```

## 1. Starting point

`tslib` (`../tslib`, Rust) is built on
[tsclientlib](https://github.com/ReSpeak/tsclientlib) and covers the TeamSpeak 3
protocol: audio, chat, channels, file transfer, permissions. Searching every
`crates/**/*.rs` and workspace `Cargo.toml` yields **no** occurrence of `video`,
`screen`, `webrtc` or `websocket`: screen sharing is supported by no layer of
the current stack.

The blocking question was whether the TS6 screen sharing protocol is reachable
at all. This recon answers **yes**, and with far less difficulty than expected.

---

## 2. Findings

### 2.1 Signaling rides on the existing TeamSpeak command channel

The binary contains TS3-style commands (isolated lowercase tokens), split by
direction following the `notify*` = server → client convention:

**Client → server**

| Command | Matching C++ payload |
|---|---|
| `setupstream` | `Publish_Session` |
| `updatestream` | `Update_Session_Command` |
| `stopstream` | `Stop_Stream` |
| `joinstreamrequest` | `Join_Stream_Request` |
| `respondjoinstreamrequest` | `Join_Stream_Response` |
| `removeclientfromstream` | `Stream_Client_Kick` |
| `streamsignaling` | `Stream_Signaling` |
| `requeststreaminfo` | — |
| `requestsfuaccessinfo` | — |

**Server → client**

| Notification | Matching C++ payload |
|---|---|
| `notifystreamstarted` | `Stream_Started` |
| `notifystreamstopped` | `Stream_Stopped` |
| `notifystreamupdated` | `Updated_Session_Notify` |
| `notifystreaminfo` | `Stream_Info` |
| `notifystreamattendees` | `Stream_Attendees` |
| `notifystreamsignaling` | `Stream_Signaling_Parsed` |
| `notifystreamclientjoined` | `Stream_Client_Joined` |
| `notifystreamclientleft` | `Stream_Client_Left` |
| `notifyjoinstreamrequest` | `Join_Stream_Request` (forwarded) |
| `notifyrespondjoinstreamrequest` | `Join_Stream_Response` (forwarded) |
| `notifysfuaccessinfo` | `SFU_Access_Info_Response` |

The command ↔ payload mapping is **inferred** from the names and must be
confirmed in Phase 2. The token list itself is literal.

> **Key implication:** these commands travel over the very connection that
> `tsproto`/`tsclientlib` already establishes and decrypts. No new transport is
> needed for signaling, and no cryptographic analysis.

`Stream_Client_Leave` also exists as a C++ payload; its wire command has not yet
been located among the strings.

### 2.2 Payloads are JSON

Demangled C++ symbols show that all the logic lives in
`com::teamspeak::video::ScreenshareManager`, which serializes with
`nlohmann::json` (`nlohmann::json_abi_v3_11_3`). Relevant signatures:

```
com::teamspeak::video::ScreenshareManager::CreateInboundSession(
    const std::variant<monostate, SessionIdentifierServer, SessionIdentifierMatrix>&,
    const std::function<void(unsigned, const std::shared_ptr<SessionInbound>&)>&)

com::teamspeak::video::ScreenshareManager::CreateOutboundSession(
    const payload::Create_New_Outbound_Session&,
    const std::function<void(unsigned, const std::shared_ptr<SessionOutbound>&)>&)

com::teamspeak::video::ScreenshareManager::OnStreamSignalingMessage(
    const std::variant<monostate, StreamIdentifierServer, StreamIdentifierMatrix>&,
    payload::Stream_Signaling_Commands_Base&&)

ClientLibPrivate::create_screenshare_interface()
com::teamspeak::video::Video_Event_Handler::Video_Event_Handler(
    I_Connection_Video&, std::function<void(const char*)>,
    std::shared_ptr<ScreenshareManager>)
```

The outbound command `std::variant` is, literally:

```cpp
std::variant<
    payload::Publish_Session,
    payload::Update_Session_Command,
    payload::Stop_Stream,
    payload::Join_Stream_Response,
    payload::Join_Stream_Request,
    payload::Stream_Client_Kick,
    payload::Stream_Client_Leave,
    payload::Stream_Signaling >
```

Every handler has signature `void(unsigned, const nlohmann::json&)` or
`void(unsigned, const std::string&, const nlohmann::json&)`: **each command body
is a JSON object**, not a list of TS3-style key=value pairs.

Other relevant symbols: `ScreenshareManager` takes an
`OpenH264DynamicLib::LoadStatus` in its constructor;
`ClientLibToScreenshareManagerInterface`, `SessionInbound`, `SessionOutbound`,
and `ServerConnectionHandler` receiving a `shared_ptr<ScreenshareManager>`.

### 2.3 The media plane is standard WebRTC

The binary embeds a full libwebrtc. Direct evidence:

- `webrtc::DesktopFrame`, `com::teamspeak::video::codec::OpenH264DynamicLib`
- `bweforvideo`, `videoGoogleMinBitrate` / `MaxBitrate` / `StartBitrate`,
  `googLibjingleSession`
- `simulcast`, `ssrc`, `offer`, `answer`, `candidate`, `subscribe`
- `kRealtimeVideo`, `kScreenshare` (WebRTC content hints),
  `IncomingVideoStream`, `NullVideoDecoder`, `video_frame_transformer`
- Hardware acceleration: `libva*` (VAAPI), Intel Media SDK (`MFXVideoDECODE_*`,
  `MFXVideoENCODE_*`), `libavcodec.so.62` / `libswscale` / `libswresample`
- Software encoders: OpenH264 loaded dynamically (for licensing reasons), plus
  VP8/VP9 from the libwebrtc stack

Note: on desktop, source capture uses PipeWire (`pw_stream_*`) and
ScreenCaptureKit on macOS (`screenshareSupport.wayland`,
`screenshareSupport.screencapturekit`). Irrelevant for viewing only.

### 2.4 Transport modes and server capabilities

Mode enum (from `main.js`, literal):

```js
NONE = 0, P2P = 1, SFU = 2
```

Support is advertised by the virtual server through the
`virtualserver_capability_extensions` property, which the client queries as:

```js
capabilityExtensions.indexOf("STREAM_P2P")
capabilityExtensions.indexOf("STREAM_SFU")
capabilityExtensions.indexOf("HTTPFT")
capabilityExtensions.indexOf("MATRIXCHAT")
capabilityExtensions.indexOf("s3")
```

The wire tokens are therefore **`STREAM_P2P`** and **`STREAM_SFU`** (the UI
constants `STREAMING_P2P` / `STREAMING_SFU` are just JS enum names).

Related server property: `virtualserver_sfu_endpoint`, editable under
"Server Edit → SFU Endpoint" and described in the UI as *"the endpoint URL of
the SFU server to use for video streaming"*. Access fields found:
`sfu_endpoint`, `sfu_token`, `sfu_user`, `sfu_user_id`.

In the Go library the equivalent struct (`types.StreamConfig`) exposes these
JSON tags:

```
json:"streamIdentifier"   json:"sfuEndpoint,omitempty"   json:"sfuUserId,omitempty"
json:"publicSessionId"    json:"mode"                    json:"access"
json:"chatId,omitempty"   json:"identifier"              json:"leave_mode"
```

### 2.5 Two session kinds

```js
SERVER = 0, MATRIX = 1
```

matching the C++ types `SessionIdentifierServer` / `SessionIdentifierMatrix` and
`StreamIdentifierServer` / `StreamIdentifierMatrix`.

- **SERVER** — screen sharing inside a virtual server channel; signaling over the
  TS connection. **This is our case.**
- **MATRIX** — screen sharing in MyTS chats; signaling through the Matrix backend
  in `libtschat_client_lib_export.so` (exported symbol `onScreenshareEvent`,
  `_cgo_b0c704e68bbd_Cfunc_onScreenshareEvent`; Go + libolm + megolm stack).
  **Out of scope**, but it shares the data structures.

### 2.6 State machine enums (literal, from `main.js`)

```js
// ScreenshareSessionStatus
ENDED = -2, FAILED = -1, NEW = 0, WAITING_FOR_RESPONSE = 1,
DISCONNECTED = 2, CONNECTING = 3, CONNECTED = 4

// source type
NONE = 0, CAMERA = 1, SCREEN = 2, WINDOW = 3, EXISTING_SESSION = 4

// ScreenshareAccessibility
NONE = 0, PUBLIC = 1, CONTACTS_ONLY = 2, PRIVATE = 3

// ScreenshareLeaveReason
NONE = 0, LEFT = 1, DENIED = 2, FAILED = 3, KICKED = 4, BANNED = 5

// session UI state
FAILED = -1, NEW = 0, MINIMIZED_PAUSED = 1, MINIMIZED = 2, PAUSED = 3, RUNNING = 4

// special identifiers
INVALID = "-2", UPDATE = "-3"
```

Status is compared by order (`status <= NEW` means "joinable", `status > NEW`
means "joining"), so the numeric values are meaningful.

### 2.7 Internal core ↔ UI API

Methods the core exposes to the UI, useful as an index of possible operations:

```
publishSession        updateSession          closeSession        deleteSession
createOutboundSession joinStreamRequest      joinStreamResponse  removeFromSession
requestStreamInfo     requestAllStreamInfos  setStreamInfoSubscribe
requestAllSessions    pauseSession           pauseAllSessions    playStream
updateSessionUiState  getScreenshareSupport  publicSessionId     serverSessionId
```

Events pushed to the UI (literal enum values):

```
screenshareSessionEvent  streamInfoReplace  streamStarted  streamStopped
streamUpdated            joinStreamRequest  peerConnectionEvent
```

Observed JS ↔ native bridge: `tsclient_internal.getScreenshareSupport`,
`subscribeAvailableSourcesWithScreenshots`,
`unsubscribeAvailableSourcesWithScreenshots`,
`setSubscribedScreenshotWhitelist`.

### 2.8 Client property

`client_streaming` / `client_is_streaming` (a client property held by the
server, surfaced to the UI as `clientStreaming`) is the flag marking that a user
is broadcasting. This is the cheapest first hook in `tslib`: we can show *who*
is sharing well before being able to decode any stream.

**Note:** no permission strings (`b_*` / `i_*`) related to stream, video or
screenshare were found in the binary. Access control appears to run through the
`ScreenshareAccessibility` enum and the `joinstreamrequest` →
`respondjoinstreamrequest` approval flow rather than the TS3 permission system.

---

## 3. Work plan

### Phase 1 — Complete the JSON schemas (static)

**Goal:** a full schema for every payload plus a state machine diagram.
**Sources:** the three files in section 0.
**Tasks:**
- extract field names for every payload object from `main.js` (the UI builds and
  consumes them in clear text);
- map `ScreenshareManager` in a disassembler only if `main.js` is not enough;
- find the missing wire command for `Stream_Client_Leave`.

**Output:** `docs/screenshare-protocol.md`.
**Risk:** none. **Estimate:** ~1 day.

**Done (2026-09-07).** `main.js` proved sufficient; no disassembler was needed.
Phase 1 also corrected three things in this document: the SFU turned out to be
**mediasoup over WebSocket** (`libmediasoupclient` + IXWebSocket), STUN servers
**are** hardcoded (§4 below is wrong), and the missing `Stream_Client_Leave`
command does not exist — leaving reuses `joinstreamrequest` with `is_remove`.

### Phase 2 — Instrumented Rust client (the decisive step)

**Goal:** capture real payloads, already decrypted.
**How:** a minimal `tsclientlib`-based binary that logs *every* incoming command,
including the ones the library currently discards as unknown (the
`notifystream*` family will land there). Connect it to a real TS6 server while a
desktop client shares its screen.
**Output:** a full transcript of one session, validating or correcting Phase 1.

> This is the packet inspection that actually pays off: interception happens
> *after* decryption, inside a library that already holds the keys. Wireshark on
> the command channel would yield nothing (EAX encryption).

**Estimate:** ~1–2 days.

### Phase 3 — Wireshark, media plane only

Once Phase 2 has revealed the SFU endpoint and credentials: confirm the video
flow is standard DTLS-SRTP, on which ports, with which codec profile (H.264
baseline via OpenH264? VP8?) and whether simulcast is used.
**Estimate:** ~0.5 days.

### Phase 4 — Viewer-only prototype (Android)

If the flow is standard WebRTC, integration is mechanical:

1. **`tslib-core`** — parse the `notifystream*` commands into new `Event`
   variants (`crates/tslib-core/src/events.rs`), tolerant of unknown fields.
2. **`tslib-jni`** — expose the events to Kotlin as JSON strings. **Do not port
   the WebRTC logic into Rust**: it would needlessly duplicate what Android
   already provides.
3. **App** — depend on `org.webrtc` (libwebrtc Android), drive a
   `PeerConnection` from the signaling JSON, render through a
   `SurfaceViewRenderer` inside an `AndroidView` in Compose.
4. Lifecycle: stream start/stop, pause, quality change, rotation, reconnection,
   and `ScreenshareLeaveReason` for error messages.

**No `MediaProjection` permission**: that is only needed to *share* the phone's
screen, not to view someone else's. The impact on `TsConnectionService` (the
foreground service) and on battery consumption does need assessing.

### Phase 5 — Compatibility testing

Against real TS6 servers, in both `STREAM_P2P` and `STREAM_SFU` modes, with a
Windows/Linux desktop client as the source.

---

## 4. Constraints and risks

- **Server availability.** Without `virtualserver_sfu_endpoint` configured, only
  P2P remains: the Android viewer receives directly from the peer, with all the
  ICE/NAT problems that implies. No hardcoded STUN or TURN server was found in
  the binary — the ICE configuration presumably arrives in the signaling, which
  is a point to clarify in Phase 2.
- **Protocol stability.** `/opt/teamspeak/docs/Extensions.md` declares the
  extension API to be in alpha state; screen sharing is just as recent. Expect
  breakage between versions and write permissive parsers.
- **Codec.** If the source negotiates H.264, a working H.264 decoder is needed:
  on Android it is hardware-backed and universally present, but the profile must
  be verified.
- **Scope.** Passive reception for interoperability only, no circumvention of
  licensing or encryption — the same ground tsclientlib already stands on.
- **Data age.** The analysis is based on a 2025-07-13 build. Re-validate against
  the current client before writing code.

## 5. Next step

Phase 1 is done. Run **Phase 2** — the instrumented `tsclientlib` client — using
the open-questions checklist in
[screenshare-protocol.md](screenshare-protocol.md) §9 as its objectives.
