# Screen sharing research — handoff

> Read this first if you're picking up the screen sharing work in a new
> session. It's a pointer, not a schema reference — the schemas live in
> [screenshare-protocol.md](screenshare-protocol.md), and the build plan for
> the next step in [screenshare-phase4-plan.md](screenshare-phase4-plan.md).

## Where things stand

- **Phase 1** (static analysis of the desktop client) — done.
- **Phase 2** (live capture) — done **for P2P mode**, in both roles, 2026-09-07,
  against `god.serod.tech:9988` (channel `Salotto`,
  `virtualserver_capability_extensions=FILETIME,STREAM_P2P`). Session 1 captured
  the viewer side, session 2 published streams from the capture client and drove
  every remaining client → server command by hand. Evidence and analysis:
  [screenshare-protocol.md](screenshare-protocol.md) §0, §9a (viewer) and §9b
  (broadcaster).
- **Blocked upstream, not merely open:** §9.6 (SFU/mediasoup payloads).
  TeamSpeak has not released the SFU — `virtualserver_sfu_endpoint` does
  nothing on a self-hosted server, there is no SFU binary to install and no
  setup documentation. §9.4 (`notifystreamattendees`) is almost certainly part
  of that same SFU path, since a full broadcaster lifecycle never triggered it.
- **Still open and testable:** §9.5, whether TURN relaying is available — it
  needs a client behind symmetric NAT (a phone on mobile data will do), not a
  different server.
- **Application code: only `client_is_streaming`.** Done — the field is
  declared in the tsclientlib fork (see AGENTS.md), flows through
  `tslib-core` → JNI → `User.isStreaming`, and shows as a green screen icon in
  `UserItem`. Everything else stays out of the app until the protocol is
  confirmed. Background: screenshare-protocol.md §0, second finding.
- **Phase 4, step 1: declarations published (2026-09-07).** The
  tsclientlib fork and its declarations submodule now have the viewer's eight
  incoming and three outgoing commands plus offline tests. Tests and a local
  dependency-override check of `tslib-core`/`stream-capture` pass. Published on
  `ts6-client-is-streaming`: declarations `9ed2a74`, tsclientlib `298e431`.
  Existing Cargo lockfiles may need a dependency refresh. Live
  typed-message delivery and bare empty `msg` server acceptance still need
  verification. See the phase-4 plan's implementation status for paths and
  integration steps. The registry, JNI, and WebRTC remain unimplemented.

## The one-paragraph version of what Phase 2 found

Screen-share notifications are **not JSON-wrapped**. They're flat TS3
`key=value` commands like any other notify. The single exception is
`notifystreamsignaling`, which packs a WebRTC message into one `json=`
parameter shaped `{"cmd":"iceCandidate","args":{mLine,mid,sdp}}` — and even
the SDP **offer** skips that command, arriving instead as a plain `offer=`
parameter on `notifyrespondjoinstreamrequest`. Full field tables: §9a.3 of
the protocol doc.

## A bug was found and fixed in `../tslib`

`examples/stream-capture/src/main.rs` called
`Connection::get_tsproto_client_mut()` immediately after `connect()`, before
the handshake finished — `connect()` returns while still `Connecting`, and
that call needs `ConnectionState::Connected`. Every run failed instantly with
`Error::NotConnected`. Fixed by waiting for `StreamItem::BookEvents` first
(same wait `tslib-core`'s `Client::do_connect` already does, at
`crates/tslib-core/src/client.rs:262`). If you see `NotConnected` again
somewhere else in `../tslib`, this is the pattern to check for.

## Re-running the capture (SFU or another P2P session)

The tool ([screenshare-phase2-plan.md](screenshare-phase2-plan.md) §4) is
interactive over stdin, which makes it awkward to drive from a coding agent —
plain `command &` inside one shell call gets killed when that call ends, so
both the capture process *and* whatever feeds it commands need the harness's
"run in background" mechanism, not a bare `&`. What worked:

```bash
cd ../tslib && mkdir -p captures
mkfifo captures/session1.stdin
: > captures/session1.cmds

# 1. Keep a writer on the FIFO open for the whole session (a bare `tail &`
#    would die with the shell call; this needs to be its own background task).
cd ../tslib/captures && tail -F -n +1 session1.cmds > session1.stdin
# (launch the above as a background task)

# 2. The capture client reads that FIFO as stdin — also a background task,
#    since it doesn't exit until told to.
cd ../tslib && RUST_LOG=info cargo run -p stream-capture -- \
  --server <host:port> --nickname "TS6DroidCapture" \
  --identity captures/identity.json --out captures/session-1 --verbose \
  < captures/session1.stdin > captures/session1.stdout.log 2>&1
# (launch the above as a background task)

# 3. To send an interactive command later, append — never write() the fifo
#    directly, or the reader thread hits EOF and stops accepting input:
echo 'joinstreamrequest id=<uuid> clid=<n> is_remove=0 msg=' >> captures/session1.cmds
```

Then poll `captures/session-1.jsonl` (or grep `captures/session1.stdout.log`
for the `>>>` highlighted lines) rather than sleeping — the harness notifies
on background-task completion, but the capture only *ends* on `/quit`, so
check the transcript file directly while it runs.

**`captures/` is real evidence, not a scratch dir — but it never goes in
git.** It's already covered by `../tslib/.gitignore`; a completed run there
carries a real public IP, LAN/Tailscale addresses and myteamspeak account
tokens. Only hand-redacted excerpts belong in `screenshare-protocol.md`.

## How session 2 probed the client → server commands

Worth reusing, because it turned guesswork into a decision procedure: send the
command with `return_code=<tag>`, then read the tagged reply. The server echoes
`return_code` on the `error` line *and* on the notification that answers the
request, so replies can be matched even when several probes are in flight. A
command that is missing something answers `error id=1542 missing required
parameter` **without naming the field**, so the method is: send a superset,
then remove one field at a time. Two constraints: pace probes ~4 s apart or
flood protection (`error id=524`) locks you out for 10 s and up, and a stale
UUID gives `error id=5635 Stream does not exist`, not 1542.

This is how `accessibility` was found — `setupstream` refuses the `access`
spelling that `notifystreamstarted` itself uses (§9b.1).

## Next steps, in order of value

1. **Phase 4, P2P viewer** — planned in
   [screenshare-phase4-plan.md](screenshare-phase4-plan.md). The signaling
   contract is complete for the viewer
   role (§9a.3, §9b) and nothing still open blocks it. Order: `tslib-core`
   parses the `notifystream*` family → `tslib-jni` forwards it → Kotlin drives
   `org.webrtc`. The first increment, `client_is_streaming`, is already done
   (§0) — unlike the `notifystream*` family it needed no `tsproto` hook, only
   an argument declaration in the tsclientlib fork (see AGENTS.md).
2. **§9.5, TURN.** Answerable without a new server: run the viewer from a phone
   on mobile data (symmetric NAT) against a sharer elsewhere and see whether
   ICE completes. This decides whether P2P is usable at all from mobile, so it
   is worth answering early in Phase 4 rather than after.
3. **§9.4 / §9.6 — wait for TeamSpeak.** Neither is reachable until the SFU
   ships. Re-check the community thread linked in §9.6 rather than spending
   effort on them.
