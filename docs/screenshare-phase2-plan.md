# Screen sharing — Phase 2 working plan

> **Status:** the capture tool is written and builds; the capture itself is
> blocked on the prerequisites in §7 (a TS6 server with a live sharer).
> Everything below was verified against `../tslib` and the vendored
> `tsclientlib` checkout `~/.cargo/git/checkouts/tsclientlib-b9d0d0212095a0c5/ee3bc6f`.

**Goal.** Capture the real, decrypted `notifystream*` traffic of one screen
sharing session, and use it to answer the six open questions in
[screenshare-protocol.md](screenshare-protocol.md) §9.

**Context.** Phase 1 is done; its output is `screenshare-protocol.md`. The
rationale and the wider roadmap are in `screenshare-research-plan.md`.

---

## 1. The finding that shapes the work

**`tsclientlib` silently discards the screen sharing commands, arguments and
all.** This rules out the obvious approach.

`InMessage` is generated from a template over a **closed list** of known
commands (`utils/ts-bookkeeping/build/MessageDeclarations.tt`). Anything outside
that list hits the fallback arm:

```rust
s => Err(ParseError::UnknownCommand(str::from_utf8(s)?.to_string())),
```

`ParseError::UnknownCommand` carries **only the command name**. The arguments
are gone by the time anyone sees it — `tsclientlib/src/lib.rs:1347` logs the
error and returns.

**Consequence:** `StreamItem::MessageEvent` will never deliver a
`notifystreamstarted`. Instrumenting `tslib-core` — the natural first instinct,
since `crates/tslib-core/src/client.rs:391` already logs every `MessageEvent` —
**cannot work**. The hook has to sit lower, where the raw bytes still exist.

## 2. Where to hook — no fork needed

An earlier draft of this plan assumed a patched fork of `tsclientlib` was
required. **It is not.** `tsproto` already exposes the raw command stream
through two public surfaces, and both sit below the parser:

**a. The event listener.** `tsproto/src/packet_codec.rs:145` emits
`Event::ReceivePacket` once per command, *after* defragmentation, decryption
and decompression and *before* `InCommandBuf::try_new` — so unknown commands
pass through it with their arguments intact. The listener list is a public
field:

```rust
// tsproto/src/connection.rs:114
pub event_listeners: Vec<EventListener>,
// :84  type EventListener = Box<dyn for<'a> Fn(&'a Event<'a>) + Send>;
```

The alias itself is private, but the type is nameable from outside, so a
listener can be pushed by writing the boxed type out in full. `Client` derefs
to `Connection`, and `tsclientlib::Connection::get_tsproto_client_mut()`
(`tsclientlib/src/lib.rs:829`) hands out the `Client` — behind the crate's
**`unstable` feature**, which the capture crate enables for itself.

**b. `ConnectOptions::log_commands(true)`.** Installs `tsproto::log::add_logger`
(`tsclientlib/src/lib.rs:495`), which `debug!`s every command in both
directions from the first packet on. Lower fidelity than (a) — it is a log line,
not a record — but it starts earlier: the listener can only be attached once
`connect()` has returned, so **the handshake, `initserver` included, is visible
only here**. That is where `virtualserver_capability_extensions` lives, which
decides P2P vs SFU (§7).

The capture tool uses both, writing (a) to a JSONL transcript and (b) to a debug
log file.

**Sending** is equally free of patching: `OutCommand::new`
(`utils/tsproto-packets/src/packets.rs:991`) appends the command name bytes
verbatim, so handing it a whole command line sends exactly those bytes —
TS3 escapes and all. That is how the tool sends arbitrary commands typed on
stdin.

## 3. The free first test

**Do this before anything else.** The `warn!` at `lib.rs:1347` fires today,
unpatched. Connect any existing `../tslib` example to a TS6 server while a
desktop client shares its screen, with warnings visible:

```
RUST_LOG=warn cargo run -p simple-bot -- --server <host>
```

The `notifystream*` command **names** should appear in the log. That confirms
§2.1 of the research plan — signaling really does ride the ordinary command
channel — for the cost of one connection, and proves the server is configured
for screen sharing before any effort goes into the capture proper.

## 4. The capture tool

`../tslib/examples/stream-capture` (a workspace member, built with
`cargo build -p stream-capture`).

```
cargo run -p stream-capture -- \
    --server <host> \
    --channel "<the sharer's channel>" \
    --out captures/session-1
```

Outputs, both written live:

| File | Content |
|---|---|
| `<out>.jsonl` | one JSON object per command packet: `t_rel`, `epoch_ms`, `dir` (`in`/`out`), `type`, `name`, `raw` (UTF-8 lossy, escaping intact), `hex` |
| `<out>.log` | full `debug` tracing, including the handshake commands the listener misses |

Interactive: anything typed on stdin is sent verbatim as a command packet, so
`joinstreamrequest …` can be probed without recompiling. `/clients` prints the
client and channel lists (to find the sharer's client id), `/quit` disconnects.
Commands whose name contains `stream`, `sfu`, `video` or `screen` are printed
prominently on stdout; `--verbose` prints all of them.

The `raw` field is the command exactly as it went over the wire — that is the
point, since §9.1 is a question about framing, and a parsed rendering would
destroy the evidence.

## 5. What to capture

One full session, logged end to end, covering:

1. idle connection (baseline),
2. a desktop client **starts** sharing → `notifystreamstarted`, `notifystreaminfo`,
3. the capture client **requests to join** → `joinstreamrequest` →
   `notifyrespondjoinstreamrequest`,
4. signaling exchange → `notifystreamsignaling` (the `kOffer` / `kAnswer` /
   `kICECandidate` / `kReconnect` shapes),
5. a second viewer joins and leaves → `notifystreamclientjoined` / `left`,
6. sharer **stops** → `notifystreamstopped`.

Steps 1, 2, 5 and 6 need nothing but a connected capture client. Step 3 needs
the argument names, which step 2 should reveal; step 4 follows from step 3.
Save the transcript — it is the evidence base for the Phase 2 revision of
`screenshare-protocol.md`.

## 6. Note on the `unstable` feature

`stream-capture` declares `tsclientlib = { workspace = true, features =
["unstable"] }`. Cargo unifies features across a workspace build, so
`cargo build --workspace` now enables `unstable` for `tslib-jni` too. This is
harmless — the feature only adds public accessors, no behaviour changes — and
building `tslib-jni` on its own (which is what `buildRustLibs` and
`build_android.sh` do) is unaffected. Verified: `cargo check -p tslib-jni`
still builds clean.

## 7. Prerequisites, and why the mode matters

- A **TS6 server** with screen sharing enabled.
- A **desktop client** to act as the sharer.
- Ideally a **second viewer** for step 5.

Whether the server has `virtualserver_sfu_endpoint` configured decides how much
Phase 2 can settle:

| Server | What gets answered | What stays open |
|---|---|---|
| **SFU configured** | everything, including §9.6 (are the mediasoup payloads stock?) and the `requestsfuaccessinfo` → `notifysfuaccessinfo` exchange | — |
| **P2P only** | §9.1–§9.4 — the framing questions, which is the bulk of the value | §9.5 TURN relaying, §9.6 mediasoup payloads |

P2P-only is still worth doing: question §9.1 blocks everything downstream and is
answered either way. Which mode applies is readable from
`virtualserver_capability_extensions` in the `initserver` line of `<out>.log`.

## 8. Success criterion

Phase 2 is done when `screenshare-protocol.md` §9 can be rewritten from captured
evidence rather than inference — above all **§9.1, how a JSON body attaches to a
TS3 command**. Nothing in `tslib-core` can parse these commands until that is
known, so it gates Phase 4 entirely.

Fold the transcript's findings back into `screenshare-protocol.md`, promoting
the *inferred* rows in §4.2 to literal and correcting them where they are wrong.

## 9. Explicitly out of scope

- **No application code.** The standing instruction in `AGENTS.md` holds: no
  screen sharing code in the app until the protocol is confirmed.
- **No Wireshark.** That is Phase 3, and only for the media plane. The command
  channel is EAX-encrypted; capturing it on the wire yields nothing, which is
  the whole reason this phase instruments a client that already holds the keys.
- **No Matrix / MyTS sessions.** Server-kind sessions only.

The one cheap increment that remains available meanwhile, and needs none of
this: the `client_is_streaming` client property, to show *who* is sharing.
