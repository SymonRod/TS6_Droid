# Screen sharing research — handoff

> Read this first if you're picking up the screen sharing work in a new
> session. It's a pointer, not a schema reference — the schemas live in
> [screenshare-protocol.md](screenshare-protocol.md).

## Where things stand

- **Phase 1** (static analysis of the desktop client) — done.
- **Phase 2** (live capture) — done **for P2P mode only**, 2026-09-07, against
  `god.serod.tech:9988` (channel `Salotto`,
  `virtualserver_capability_extensions=FILETIME,STREAM_P2P`). Evidence and
  analysis: [screenshare-protocol.md](screenshare-protocol.md) §0 and §9a.
- **Still open, needs a server with `virtualserver_sfu_endpoint` configured**:
  §9.5 (is TURN relaying available) and §9.6 (are the SFU/mediasoup payloads
  stock). Same tool, same procedure — see "Re-running the capture" below.
- **No application code yet.** Per AGENTS.md, screen sharing stays out of the
  app until the protocol is confirmed. The one exception that needs none of
  it: `client_is_streaming`, a plain client property — see
  screenshare-protocol.md §0, second finding.

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

## Next steps, in order of value

1. Find or stand up a TS6 server with `virtualserver_sfu_endpoint` set, to
   close §9.5/§9.6 — this is the only thing P2P testing can't reach.
2. Figure out what triggers `notifystreamattendees` — never seen in the P2P
   session; possibly a dedicated request command not yet identified, or it
   only fires above some viewer count.
3. Exercise `setupstream`/`updatestream`/`stopstream`/`removeclientfromstream`
   from the client side (the P2P session only ever observed the *receiving*
   end of a share someone else started) to confirm those bodies are flat too.
4. Once §9 is fully closed: Phase 4 per screenshare-research-plan.md — still
   gated on "no application code" until then.
