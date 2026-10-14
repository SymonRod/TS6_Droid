# myTeamSpeak account-key unwrap — run41 reference

**Status: version-2 account-key unwrap demonstrated end to end (2026-10-14).**
One authorized desktop password login, using an isolated profile and the owner's
test credentials, returned HTTP 200 / protobuf `ERROR_LOGIN_OK=200`. An offline
implementation authenticated the server's wrapped key and reproduced the native
32-byte output exactly. This is **not yet a standalone sync-item decryptor or a
Flutter/Rust implementation**.

**Offline follow-up:** the resulting account key now reproduces every captured
bookmark/item plaintext and its SHA-512 integrity suffix. See the
[bookmark decryption reference](myteamspeak-bookmark-decryption-protocol.md).
The item format is unversioned AES-256-CTR-128LE, **not this GCM envelope**;
its exposed unkeyed digest is not an authenticity guarantee. The original
run41 findings and historical scope below are retained for provenance.

Related references: [login](myteamspeak-login-protocol.md),
[sync](myteamspeak-sync-protocol.md), [previous handoff](myteamspeak-login-run40.md).

## 1. Demonstrated algorithm

**Rust integration update (2026-10-14):** the demonstrated unwrap now lives in
`tslib-myts`, with binary key preservation in login and synthetic/offline tests.
See [read-only Rust engine](myteamspeak-rust-import-engine.md) for integration,
memory/lifecycle limits and remaining Flutter work. Historical run41 status and
evidence below are retained; this does not add a new real-account validation.

Let `P` be UTF-8 password bytes and `E` UTF-8 email bytes with ASCII `A..Z`
lowercased (same demonstrated normalization as the login KDF):

```text
encryption_value = PBKDF2-HMAC-SHA512(P, E || "ts3Encryption" || P, 10000, 32)

LoginSession.key = version[1] || tag[16] || nonce[12] || ciphertext[32]
version = 0x02

account_key = AES-256-GCM.decrypt_and_verify(
    key=encryption_value, nonce=nonce, ciphertext=ciphertext, tag=tag, AAD=empty
)
```

The observed envelope is **61 bytes**, and the authenticated plaintext is
**32 bytes**. It is raw binary, not Base64, hex or protobuf. The tag precedes
the nonce and ciphertext; do not assume the common `nonce || ciphertext || tag`
layout. The version byte is outside the GCM input in this demonstrated flow.
It must be checked explicitly, not ignored or stripped indiscriminately.

There is **no additional SHA-512, HKDF, recovery-key RPC or password-to-hex step**
between the demonstrated encryption KDF and this account-key unwrap. This does
not establish how the resulting key is used for individual sync items.

Research implementation: `tools/myts/unwrap.py`. It deliberately supports only
this demonstrated version/length and fails closed for everything else.

## 2. Evidence path and native anchors

Binary: `../teamspeak/TeamSpeak`, 79,757,920 bytes,
MD5 `7eb9fdb89d3da783d3db55845c5066ca` (same build as runs 39–40).
All addresses below are ELF virtual addresses relative to the PIE load base,
**not offsets to hardcode in application code**.

| Observation point | Address | Observed inputs/output |
|---|---|---|
| Encryption KDF | `0x2a7fe30` | 32-byte result |
| HTTP request sender | `0x46d9559` | `rsi=URL`, `rcx=framed request`; login 134 bytes |
| HTTP 200 response parse call | `0x46d9b2b` | `rdi=response protobuf object`, `rsi=body`, `rdx=length`; login 1101 bytes |
| Authenticated blob splitter | `0x2a82760` | `rdi=sret`, `rsi=provider`, `rdx=60-byte envelope body`, `rcx=32-byte encryption value`; returns 32 bytes |
| Authenticated crypto core | `0x2a819b0` | `rdx=32-byte key`, `rcx=12-byte nonce`, `r8=32-byte ciphertext`, `r9=1`; returns plaintext string plus 16-byte tag string |

The splitter's native stack was:

```text
0x2a82760 <- 0x2a811c8 <- 0x2a2de77 <- 0x2a30118 <- 0x2a2f7d7
```

The following comparisons **all passed**, using private local files, without
printing bytes or secret hashes:

1. The parsed `LoginSession.key[1:]` equals the native splitter's input exactly.
2. The independently calculated `ts3Encryption` value equals both the captured
   KDF output and the splitter/core's key argument.
3. The native input equals `tag || nonce || ciphertext` from the core captures.
4. PyCryptodome AES-GCM with empty AAD verifies the tag and returns exactly the
   native core and splitter plaintexts.
5. Altering the ciphertext is rejected by the offline reference.

The same buffers did **not** authenticate as AES-EAX. This account-key result
does not depend on the older, incorrect assumption that all native EAX calls
are sync-item decryptions; many old EAX hooks actually observed TS voice/command
traffic. See the comments in `tools/myts/gdb_aead.py` for that historical limit.

The new-build descriptor import closure (12 of 67 recovered descriptors) was
saved locally for decoding. It was not rendered or protoc-round-trip verified
as replacement committed schemas.

## 3. Synthetic golden and offline checks

These values are fabricated, **not account data**:

```text
email = Alice@EXAMPLE.COM
password = correct horse battery staple
encryption_value = 92e837501d0748edbbd279e32f49931626851ca6d97b5658e3c522c533654e45
account_key = bytes 00 through 1f
nonce = bytes 00 through 0b
wrapped_key (hex, concatenate lines):
02323ec445370cb098574647e56416e082
000102030405060708090a0b
df3d396ab4b8ccefbfd431d67420448f56791f8f13c313943db655c533aaf63b
```

Run from the repository root, using the isolated research environment:

```bash
captures/myts/.venv/bin/python -m unittest discover -s tools/myts -p 'test_*.py'
captures/myts/.venv/bin/python tools/myts/verify_unwrap_capture.py \
  --capture captures/myts/run41b/probe \
  --descriptors captures/myts/build-7eb9fdb8 --env .env
```

The second command is **offline**, does not create a session, and prints only
metadata/verification outcomes. `--env` is optional: omit it to recheck the
server/native/GCM correlation without rereading credentials.

All 15 tests passed: five login goldens and ten unwrap tests covering the
encryption derivation, synthetic envelope, AES-256-GCM known-answer vector,
wrong password, every altered tag/nonce/ciphertext byte, unknown versions,
truncation/extension and wrong key lengths. Production Rust must port these
checks rather than silently accepting bytes from a failed authentication.

## 4. Research environment, private artifacts and cleanup

- The owner authorized running this binary with `.env` test credentials.
  This checkout uses `EMAIL` and `PASSWORD`; no values were passed in argv.
- Network traffic used a temporary Docker container sharing
  `wstgw-gw-1`'s network namespace, the gateway already running from
  `~/infra/wstunnel-gw`. DNS was the gateway's `1.1.1.1` resolver, routed
  through its tunnel. No TLS interception or certificate-validation bypass.
- Host `/usr` and the supplied binary were read-only mounts; the research
  captures/profile were writable. The successful container also had read-only
  UID/group data and the WSLg PulseAudio socket. Xvfb provided a private display.
- GDB launched the client as its child with container-scoped ptrace support;
  no host `ptrace_scope` change or late attach. CEF used `--no-sandbox` only in
  this disposable research container. CDP port 9226 was loopback-only there.
- The first container failed at startup with SIGSEGV **before any login**.
  Its files remain under `captures/myts/run41/`; successful evidence is
  `captures/myts/run41b/`. Do not confuse these two attempts.
- Native startup performed its normal account sync, including a captured
  `requestServerItems` reply (3756 bytes). No bookmark, identity, contact or
  account setting was manually changed. This was not a write-disabled client.
- Only **one account login** was submitted. The isolated desktop logout
  returned callback code 0, but a subsequent `/authentication:session` check
  still returned `ERROR_SESSION_OK=102`. Therefore the research session was
  explicitly deleted: `deleteSession` returned **204**, through the gateway.
  Do not equate a desktop logout callback with confirmed server deletion.
- Both temporary research containers were removed; the owner's gateway/demo
  containers were not stopped, reconfigured or removed.

Sensitive buffers remain in ignored `captures/myts/run41b/probe/`, with private
directory/file permissions. `metadata.log` records lengths and stack addresses
only. The disposable driver is retained at `captures/myts/run41/drive.py`.
Do not commit profiles, responses, keys, sessions, plaintext items or `.env`.

Reusable tools added: `gdb_unwrap_probe.py`, `unwrap.py`,
`verify_unwrap_capture.py`, `test_unwrap.py` under `tools/myts/`.
No Flutter, Kotlin or external Rust application source was changed in this round.

## 5. Next milestone and scope limits

The account-key unwrap is now solved **for the demonstrated version-2 flow**;
other envelope versions, alternate login/recovery/renewal modes and different
account-key lengths remain untested.

The subsequent [offline item follow-up](myteamspeak-bookmark-decryption-protocol.md)
completed this next step, with a Rust item primitive in `../ts6-lib`; the
following paragraph records what remained open at the end of run41:

Next, follow the **resulting account key into the sync-item key provider**.
The captured pull also reached the native `0x2a82e60` IV16 decrypt path and
SHA-512 wrapper `0x2a82110`, with outputs of 159, 233, 277, 319, etc. bytes.
Those observations provide inputs/outputs for the next offline comparison,
but this round has not established their key derivations, full item framing or
integrity rules. In particular, **do not apply the account-key GCM envelope
directly to an `item_blob`**.

Application integration belongs in `tslib-myts` (exposed through `tslib-frb`),
not a new Dart cryptographic implementation. The current app success model
only returns session/UUID/username; it must eventually preserve the wrapped
key and derive/open it while password input is available, without persisting
the password. Secret key storage and lifecycle require explicit design.
The `../tslib` checkout is absent on this machine, so no Rust port was attempted.

Keep token renewal and read-only bookmark import as independent milestones.
