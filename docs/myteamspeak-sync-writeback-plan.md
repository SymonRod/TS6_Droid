# myTeamSpeak sync write-back plan (bookmarks + identity in use)

**Status: plan only (2026-10-15). No writer is implemented.**
Read-only import is delivered and owner-tested live; see
[the import-engine handoff](myteamspeak-rust-import-engine.md). This document
defines the next capability: automatic two-way bookmark synchronization with a
single total opt-out, including publishing which identity a bookmark uses.

## 1. Goal

- Imported bookmarks stay synchronized with the myTeamSpeak account in both
  directions without manual import/export steps.
- The identity the user chose for a bookmark is published to the cloud, so the
  desktop client and other devices see the same mapping.
- One account-sync setting opts out of **both** push and pull. While off, the
  app never contacts `/synchronization` and never needs the account key in
  memory. Re-enabling triggers a bounded re-pull, never an implicit push.

Non-goals for this delivery: contacts/account-chat writes, avatar upload,
 Matrix key publication, multi-account switching, background periodic sync
 (sync runs on app foreground actions and explicit refresh only).

## 2. Established facts this plan relies on

- `Bookmark_Data.identity` (field 6) is the **cloud `item_uuid` of the
  identity**. Proven 2026-10-15 on the disposable test account: 2/2 nonempty
  references matched an identity item UUID; no match on `id_name`, nickname,
  UID or private string. See the import-engine handoff §"Nonempty
  bookmark-reference gate".
- **"Use Default" is an explicitly present empty string**, not an absent
  field. The decoder already distinguishes absent vs empty.
- `is_default` is a stored per-identity flag; several `true` values coexist.
  Pressing desktop "Use as Default" moves the flag (new identity `false`→
  `true`, one old identity `true`→`false`). The effective-default rule for
  empty references under several `true` flags is suspected-recency, unproven.
- Item encryption is known: `IV[16] || AES-256-CTR-128LE(account_key,
  plaintext) || SHA512(plaintext)[64]`, exact protobuf bytes hashed before
  parsing. TLS verification and receive caps stay as in the read path.
- `synchronizeItems` pushes local changes; each push returns a new
  `globalversion` (run6 evidence). Reply statuses: `IN_SYNC=300`,
  `NOT_IN_SYNC=301`, `NOT_IN_DB=302`, `COLLISION=303`, `OVERLIMIT=304`.

## 3. Architecture (same boundary as import)

Protocol/crypto in `tslib-myts` (`../ts6-lib`), sans-IO, exposed through
`tslib-frb`; Flutter owns transport, cursors, settings and UI.

### 3.1 Rust (`tslib-myts`)

1. `encrypt_item(account_key, item_data_plaintext) -> blob` mirroring
   `decrypt_item`, with constant-time digest handling and zeroization.
2. Typed builders: `build_sync_push(session, globalversion, class_versions,
   changed_details)` for BOOKMARK/IDENTITY classes, reusing the bounded
   `Writer`/`SyncLimits` discipline of `build_initial_pull`.
3. `parse_sync_push(status, body)` classifying `IN_SYNC` (advance cursors),
   `COLLISION` (server copy wins; surface to UI, never auto-overwrite),
   `OVERLIMIT`/`NOT_IN_DB`/session-expiry (fail closed with typed errors).
4. Identity content encoder for `Identity_Data` (strict-validated strings
   only; never generate or "improve" key material).
5. No credential persistence, no renewal-token handling, no background task.

### 3.2 Flutter/Dart

1. **Cursor store** (next to `AccountVault`, same atomic-write discipline):
   `globalversion`, per-class `version`, per-item `item_version`. Updated only
   on accepted `IN_SYNC`.
2. **Transport**: reuse `MyTsApi` policy (verified TLS, no redirects/retries,
   1 MiB login / 8 MiB sync caps on decompressed bytes, 15 s connect +
   45 s overall deadlines).
3. **Push triggers** (foreground only): bookmark edited/created/deleted in app,
   identity link changed for an imported bookmark, identity renamed. Each push
   carries only the changed `detail` entries with freshly encrypted blobs and
   bumped outer `item_version`s.
4. **"Identity in use" publication**: setting a bookmark's identity writes the
   chosen identity's cloud `item_uuid` into `Bookmark_Data.identity` and
   pushes that bookmark. Choosing "Use Default" writes an explicitly empty
   string. The local `links` map stays the source of truth until `IN_SYNC`.
5. **Opt-out setting** (`syncEnabled`, default on): when off, skip pull and
   push, drop the in-memory account key, keep cursors and vault untouched.
   Turning it back on runs one bounded pull; conflicts surface, nothing is
   force-pushed.
6. **Key lifecycle**: push/pull need the unwrapped account key. Reuse the
   existing unlock flow (password at hand or explicitly remembered password);
   without it, sync actions fail closed with a sign-in prompt. The raw key is
   never persisted; only the existing opaque Rust handle lives during the call.
7. **Conflict UX**: counts-only preview like import; `COLLISION` keeps the
   server copy and offers explicit keep-mine (re-push with fresh version) or
   take-server. Tombstones/deletions are surfaced, never auto-applied in this
   delivery.
8. **Import policy change**: with the resolver proven, a nonempty cloud
   reference auto-links the matching local identity by cloud ID at import;
   empty references keep asking once with no preselection. Same-cloud-ID
   content mismatch stays a reported conflict; stored data is never replaced
   silently.

## 4. Delivery sequence

1. Rust writer + round-trip property tests (decrypt(encrypt(x)) == x,
   tamper rejection, limits, `COLLISION` classification) — offline only.
2. FRB exposure + cursor store + opt-out setting plumbed through, push/pull
   disabled behind a feature flag — offline tests.
3. Bounded live validation on the disposable test account with explicit
   authorization per run: single-bookmark push → re-pull equality;
   collision path (desktop edits same bookmark meanwhile); opt-out on/off
   (no `/synchronization` traffic while off); remembered-identity publication
   visible on desktop. No production-account or background testing.
4. Owner acceptance on their account only after test-account green.

## 5. Acceptance criteria

- Fresh import auto-links bookmarks whose cloud reference names a known
  identity UUID; empty ones ask once, remembered per bookmark.
- Editing a bookmark or its identity in-app appears on desktop after sync,
  and desktop edits appear in-app after pull/refresh.
- Repeat push/pull with no changes is a no-op (cursor-advanced `IN_SYNC`).
- Opt-out off: zero sync traffic (verifiable by absence of calls, not by
  absence of changes); vault, cursors and local data intact.
- Conflicts never silently overwrite either side; every failure is typed and
  recoverable; no secret (password, key, token, private identity) is logged,
  persisted outside secure storage, or committed to fixtures/docs.
- Synthetic suites green: `tslib-myts` + FRB conversion + Flutter
  vault/cursor/transport/UI tests; `flutter analyze` clean of new lints.

## 6. Risks

- Effective-default under several `is_default=true` is unproven; empty-ref
  auto-resolution stays manual until proven, so no wrong-identity connection
  can result from it.
- `OVERLIMIT`/`NOT_IN_DB` recovery and session renewal are fail-closed paths
  that need live test-account evidence before release.
- Dart/FRB `String` copies of secrets are not zeroizable; minimize their
  lifetime and never log them.
