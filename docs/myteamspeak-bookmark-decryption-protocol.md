# myTeamSpeak bookmark decryption — offline item reference

**Status: complete offline decryption and integrity checking demonstrated for
all five run41b bookmarks (2026-10-14).** The same provider also reproduces the
two identity and one config item, without importing or displaying their data.
No new login, network call, desktop launch, session or cloud change was needed.

Related: [account-key unwrap](myteamspeak-key-unwrap-protocol.md),
[sync envelope and payload schemas](myteamspeak-sync-protocol.md),
[password login](myteamspeak-login-protocol.md).

## 1. Demonstrated chain and exact framing

First authenticate and unwrap `LoginSession.key` using the **separate GCM
account-key protocol**. Let `K` be the resulting raw 32-byte account key and
`P` the serialized `com.teamspeak.sync.proto.Item_Data`:

```text
item_blob = IV[16] || ciphertext[len(P)] || plain_hash[64]
ciphertext = AES-256-CTR-128LE(K, IV, P)
plain_hash = SHA512(P)                 # raw 64-byte digest, not hex/Base64

P = AES-256-CTR-128LE(K, IV, ciphertext)
accept P only if constant_time_equal(SHA512(P), plain_hash)
```

- **No item version byte.** The first byte is part of the IV, not `0x02`.
  The GCM wrapper version describes the account-key envelope, not these items.
- **No additional KDF** between the unwrapped account key and this item
  provider. Applying the raw account key reproduces every native output.
  Neither `ts3Encryption` directly nor a hash of the account key is the item key.
- **128-bit little-endian counter**, initialized with the entire IV. For block
  `j`, the keystream is `AES256(K, LE128((LE128_decode(IV) + j) mod 2^128))`.
  Block zero uses the IV **before** incrementing. Carry propagates from byte 0
  toward byte 15. Do not substitute the common big-endian CTR or a 32/64-bit
  counter flavor.
- Arbitrary nonempty plaintext length, including partial AES blocks; **no
  padding**. Observed blob length is exactly `len(P) + 80`.
- The SHA-512 covers the **exact decrypted protobuf bytes**, not ciphertext,
  IV, outer item UUID, outer item version or a reserialized/normalized message.
  Do not parse, expose or import the plaintext before checking it.

This reference supports only the observed provider. Alternate sync versions,
recovery/renewal modes and other item classes have not been established merely
by naming this provider.

## 2. Integrity is not authenticity

The native check uses an **unkeyed, exposed SHA-512 digest**, not HMAC, GCM,
EAX or another authenticated encryption scheme. Reproducing that check is
necessary for compatibility, but **does not prove an item is authentic**.

A synthetic regression test demonstrates the limit. An attacker who knows
plaintext `P` can choose a same-length replacement `P'`, form
`C' = C XOR P XOR P'`, and replace the digest with `SHA512(P')`, without knowing
the account key. The native-format integrity rule accepts the replacement.
Changing the fabricated bookmark's `Lobby` to `Other` exercises this case.
It is an offline test only; no real/cloud item was modified.

Consequently, keep normal HTTPS certificate verification and trusted-source
boundaries. Do not describe this format as AEAD or use it as a fallback when
GCM account-key authentication fails. Outer sync metadata is not included in
this digest. Structural/class/UUID checks are additional validation, not a MAC.

## 3. Provider trace and build-pinned evidence

Binary verified before disassembly: `../teamspeak/TeamSpeak`, **79,757,920
bytes**, MD5 **`7eb9fdb89d3da783d3db55845c5066ca`**. These are ELF virtual
addresses relative to the PIE base, not application offsets.

| Anchor | What establishes the chain |
|---|---|
| `0x2a80ff0`, unwrap return `0x2a811c8` | Stores authenticated account plaintext at account encryption object's `+0x10`; calls provider vtable `+0x70` with that string at `0x2a8120f` |
| Provider vtable `0x4a77d98`, constructor `0x2a81f80` | Allocates separate AES providers at `+0x20` and `+0x28`; sets key size 32, IV size 16 and account GCM nonce size 12 |
| Vtable `+0x70` → `0x2a830e0` | Requires the 32-byte length and installs the supplied account key in AES provider `+0x20`, without hashing/deriving it |
| Item reader call `0x2a7b1d3` → `0x2a803f0` → `0x2a80410` | Receives the whole `item_blob`; removes its last 64 bytes, dispatches the remaining IV/ciphertext through vtable `+0x58`, hashes the plaintext through `+0x18`, compares 64 bytes and returns empty on failure |
| Vtable `+0x58` → `0x2a82e50` → `0x2a82e60` | Selects the same AES provider `+0x20`; splits IV16 from ciphertext and invokes `0x2a83440` |
| AES key setter `0x4758c20` | Passes the raw key into the AES setup with `edx=0x100` (256 bits) |
| Provider core `0x4758c90` / CTR helper `0x3c03510` | AES counter-mode processing; wrapper explicitly increments bytes 0→15 and cancels the inner helper's big-endian increment. Net progression is full-width little-endian |
| SHA wrapper `0x2a82110`, comparison at `0x2a80601` | Raw SHA-512 of plaintext; native compares it to the exposed suffix. Reference/Rust use constant-time comparisons |

The trace is static analysis of the checked build plus the existing native
input/output captures. No new debugger run was made. The original probe did
not separately capture every provider object's address/key installation;
the decisive dynamic evidence is an independent match of **all** native
plaintext bytes using the authenticated account key, together with the
static installation/dispatch path above.

### Server/native/offline correlation

Input: **`captures/myts/run41b/probe/`**, not the failed pre-login `run41/`.
Current-build descriptors: `captures/myts/build-7eb9fdb8/`.

1. Parse successful login and authenticate its wrapped account key; compare
   with native account plaintext. No credential reread is needed.
2. Parse captured `requestServerItems` HTTP-200 reply, status **301**.
3. Match each whole server blob minus its last 64 bytes with exactly one
   captured `iv16-decrypt-rdx.bin` input. Do not infer matches by length/order.
4. Decrypt with the unwrapped account key; compare exact bytes with native
   `iv16-decrypt-result0.bin` and subsequent SHA wrapper input.
5. Compare independently computed SHA-512 with both the server suffix and
   native `sha512-string-result0.bin`.
6. Decode verified `Item_Data`, check class/content and the decrypted UUID
   against outer `detail.item_uuid`. Print only shape/lengths/outcomes.

All comparisons passed:

| Class/content | Native decrypt sequences | Plaintext sizes | Whole blob sizes |
|---|---|---|---|
| BOOKMARK / bookmark | 012, 014, 016, 018, 020 | 159, 233, 277, 319, 277 | 239, 313, 357, 399, 357 |
| IDENTITY / identity | 022, 024 | 378, 374 | 458, 454 |
| CONFIG / config | 026 | 275 | 355 |

Offline single-byte changes to IV, ciphertext and digest were rejected. This
does not claim that malicious coordinated changes are authenticated (§2).

## 4. Decrypted bookmark format

The decrypted bytes parse as the recovered **proto2 `Item_Data`**, whose
`bookmark` oneof field is **16**, containing `Bookmark_Data` (not JSON,
compression, a desktop database record or a directly serialized bookmark).
See [sync §5](myteamspeak-sync-protocol.md#5-item-payloads-sync_serializingproto-package-comteamspeaksyncproto)
and `docs/proto/Sync_Serializing.proto` for the full field table.

Important fields for the future Flutter import:

| Field | Number/type | Meaning |
|---|---|---|
| `Item_Data.item_uuid` | 2/string | Matches outer `detail.item_uuid` for all captured items |
| `Item_Data.sync_version_uuid` | 3/string | **Does not equal** outer `detail.item_version` in these captures; do not invent equality or cursor semantics |
| `Item_Data.manipulated` | 4/enum | Preserve proto2 presence/default distinction |
| `Item_Data.item_type` | 6/uint32 | Do not assume equality with outer `Item_Class`; validate the content oneof independently |
| `Item_Data.parent`, `sort_order`, `timestamp` | 7/string, 8/string, 9/uint64 | Metadata separate from the bookmark's connection fields |
| `Bookmark_Data.name`, `address`, `port` | 1/string, 2/string, 3/uint32 | Port is separate; do not assume every address already includes it |
| `nickname`, `identity` | 4/string, 6/string | Identity reference is not authorization to replace the app's identity |
| `server_password` | 7/string | Secret, as are channel passwords |
| `default_channel`, `default_channel_password`, `default_channel_id` | 8/string, 9/string, 10/uint64 | Preserve distinctions; channel password is not server password |
| `server_uid` | 15/string | Possible stable server dedup key; import policy remains separate |
| `send_mytsid_on_server` | 22/bool, default true | Absent is not false |
| `connect_muted` | 25/bool, default false | Proto2 presence is available |

The current-build recovered descriptors declare these same bookmark/item
fields as the committed older snapshot. This round used those descriptors
directly; it did **not** regenerate/round-trip verify replacement `.proto`
files or establish complete compatibility for every descriptor/message.

## 5. Synthetic tests, Rust port and reproduction

Research reference: `tools/myts/item.py`; goldens: `item_vectors.py`; tests:
`test_item.py`; independent correlation tool: `verify_item_capture.py`.

The fabricated golden uses account key bytes **00…1f**, IV bytes **00…0f**,
`item_uuid="synthetic-item"`, `sync_version_uuid="synthetic-version"`,
`manipulated=3`, explicitly present `item_type=0`, and a bookmark named
`Synthetic bookmark` at `voice.example.invalid`, port **9987**, nickname
`Alice 🔑`, password `synthetic password`, channel `Lobby` and
`send_mytsid_on_server=true`. Plaintext is **130 bytes**, blob **210 bytes**.
Both exact hex vectors are committed in `item_vectors.py` and mirrored in
Rust tests; no real values/hashes were promoted into fixtures.

Coverage includes FIPS-197 AES-256 first-block KAT, full-width LE counter carry
across 64 bits, partial/block boundaries, wrong key/length, every single-byte
mutation, every truncated prefix, extension, empty content, wrongly prepended
account version, ciphertext-vs-plaintext digest, and the known-plaintext
substitution limit. Python additionally tests synthetic GCM account unwrap →
item decrypt; the capture checker validates the synthetic bookmark fields and
proto2 presence using the recovered descriptors.

```bash
# TS6_Droid root: no network, no new session, no .env required
captures/myts/.venv/bin/python -m unittest discover -s tools/myts -p 'test_*.py'
captures/myts/.venv/bin/python tools/myts/verify_item_capture.py \
  --capture captures/myts/run41b/probe \
  --descriptors captures/myts/build-7eb9fdb8

# Rust checkout discovered at ../ts6-lib (../tslib is absent on this machine)
cargo test --offline --manifest-path ../ts6-lib/Cargo.toml -p tslib-myts
cargo run --offline --manifest-path ../ts6-lib/Cargo.toml -p tslib-myts \
  --example verify_item_capture -- "$PWD/captures/myts/run41b/probe"
```

Results: **26 Python tests and 26 Rust tests passed**. The Rust example also
matched all eight native plaintexts using the captured native account key;
the Python verifier separately establishes server-blob correlation and the
preceding authenticated unwrap. `cargo clippy --offline -p tslib-myts
--all-targets -- -D warnings` is blocked by a pre-existing needless-borrow
warning at `src/password.rs:65`, not by the new item module.

Application crypto was added only to `../ts6-lib/crates/tslib-myts/src/item.rs`.
`decrypt_item` returns `Zeroizing<Vec<u8>>` only after constant-time digest
comparison; failed plaintext buffers and the AES key schedule are zeroized
on drop. It uses RustCrypto `aes 0.8`, `ctr 0.9` (`Ctr128LE`) and `subtle 2`,
already available offline in this workspace. No Kotlin, Dart crypto or
generated Flutter bridge code was changed in this follow-up.

## 6. Remaining application work and safety boundary

**Rust engine update (2026-10-14):** version-2 account unwrap and bounded typed
read-only sync decoding are now integrated in `tslib-myts` and tested with only
synthetic/offline data. See [engine handoff](myteamspeak-rust-import-engine.md).
The earlier checklist below records the state after the item-primitive work;
identity UID compatibility, FRB/Flutter import, secure persistence and renewal
are still separate, unimplemented milestones.

- Port the separate demonstrated account-key GCM unwrap into `tslib-myts`,
  preserve wrapped key bytes in login success, and define secure key
  lifecycle/storage while password input is still available. Do not persist
  the password or conflate restoring a session with restoring the account key.
- Add typed sync/bookmark decoding and explicit read-only import through
  `tslib-frb`, with reply/item limits, UUID/class checks, deleted-item handling,
  optional-field semantics and dedup/import policy. The current Rust addition
  is a crypto primitive, **not an integrated Flutter importer**.
- Resolve sync version/cursor/deletion semantics independently. Do not push
  local bookmarks, silently replace identities or touch chat credentials.
- Renewal/recovery, other key versions and alternate providers remain open.

All existing capture files remain private and ignored. No secrets or real
bookmarks were printed, copied into committed fixtures or sent to a service.
No session was created, so no additional deletion was necessary; run41b's
previous verified deletion (204) remains its cleanup evidence. The gateway
was not changed, stopped, tested or used; TLS was not bypassed. Pre-existing
changes in both repositories were preserved, and no commit was made.
