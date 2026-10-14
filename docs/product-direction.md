# Product direction — desktop parity and myTeamSpeak onboarding

**Agreed with the project owner: 2026-10-14.**
**Implementation target: the Flutter app.** This document records product
requirements, not a claim that these features already exist.

## 1. Long-term goal

TS6 Droid should reach **near feature-for-feature parity with the TeamSpeak
desktop client**, adapted to Android. It is not intended to remain only a
minimal voice/server client.

Contacts and account-based chat are part of this long-term goal, even though
they are not ready for implementation today. A feature deferred from an early
milestone is **not a permanent product non-goal**. Desktop-only interactions
may need mobile equivalents; exact exceptions require an explicit decision,
not an assumption that the feature is unwanted.

## 2. First-launch experience

Before creating a local identity or opening the normal connection flow, an
unconfigured app offers two choices:

- **Sign in with myTeamSpeak.** Explain that, on an empty app, signing in also
  imports the supported account data automatically.
- **Skip.** Continue without an account, create a local identity and keep the
  normal server-client functionality available. Signing in remains possible
  later from the app.

This is a first-setup step, not a prompt that should recur on every launch.
Existing installations must be recognized and their data preserved.

### Sign-in with no pre-existing local data

After successful authentication, automatically import **all supported data
that is actually synchronized to the account**, without a separate manual
import/identity-confirmation step for this empty-app path.

The first delivery covers:

- Synced TeamSpeak identities, including multiple identities and the account's
  default-identity information.
- Server bookmarks, including supported connection fields such as address,
  port, nickname, server password and default-channel settings.
- The relationship between each bookmark and its identity. Do not connect all
  imported bookmarks using a newly generated or arbitrarily chosen identity.

Use the imported identity for the corresponding server connections, preserving
its UID and the server-side permissions associated with it. Login cannot
recover a desktop-local identity or bookmark that was never cloud-synchronized.

Do not generate a local identity before this choice and then treat its mere
existence as proof that the user already configured the app.

### Sign-in with existing local data

Do not silently replace a local identity or overwrite user data. Offer an
explicit import/merge flow that preserves existing identities and bookmarks,
handles duplicates and asks before conflicts or identity replacements.

Signing in after choosing Skip belongs to this path. Near desktop parity does
not authorize destructive replacement of an existing local setup.

## 3. Meaning of “import everything”

“Everything” means **all account data supported by the app at that delivery**,
not an assurance that every desktop field or subsystem already works.

Initially this means identities and bookmarks. Contacts and account-based chat
must be added as their implementations become ready. Make unsupported data and
fields clear rather than claiming a complete desktop-account restoration.

These are separate capabilities:

1. Initial automatic import on a fresh setup.
2. Ongoing account synchronization, including updates, deletions, conflicts,
   offline behavior and session renewal.
3. Account chat: messaging, rooms, presence and encryption/key lifecycle.

A contact roster imported through myTeamSpeak sync does not implement chat.
Legacy cloud sync (system A) and TS6 account chat (system B) remain separate
technical integrations, but **both belong to the product roadmap**. Existing
server/channel/private chat is not a substitute for account-based chat.

## 4. Delivery sequence and architecture constraints

The myTeamSpeak direction is:

1. First-launch Sign in/Skip flow and safe automatic identity/bookmark import.
2. Ongoing synchronization and session/key lifecycle hardening.
3. Contacts and account-based chat through their separately verified protocols.
4. Further desktop capabilities, prioritized and verified incrementally.

This is not a schedule or a complete desktop feature inventory. It does not
reorder unrelated work automatically.

Support multiple identities and stable bookmark-to-identity references from
the first import delivery. Preserve cloud item IDs and account ownership so
later sync and merge do not depend only on display names or server addresses.
Keep protocol/crypto logic in `tslib-myts`, exposed through `tslib-frb`, with
Flutter handling transport, persistence and UI as in the current architecture.

Initial import is a **read-only cloud operation**. Write-back is a separate
later capability, requiring conflict/deletion semantics and user-facing policy.

## 5. Safety and acceptance criteria for the first delivery

- Fresh setup + Sign in + valid cloud identities/bookmarks imports them
  automatically and preserves the correct identity for each bookmark.
- Fresh setup + Skip creates a usable local identity without requiring login.
- Completed setup is remembered across app restarts; login remains accessible.
- An existing local setup is never classified as empty merely because it has
  no bookmarks. Unreadable/corrupt local data must not be treated as absent.
- Repeat import/retry does not create duplicates or regenerate identities.
- Failed login, decryption, validation or persistence offers a recoverable
  error. Import must not leave an inconsistent half-applied setup or mark
  onboarding complete before its chosen path succeeds.
- Missing identity references must not silently connect with another identity.
- Existing local data survives failed sync and remains usable offline.
- Passwords are not persisted. Identities/private keys, session tokens and
  account keys require appropriate secure storage/lifecycle and must not
  appear in logs, documentation, fixtures or source control.
- Tests use synthetic data by default. Real-account/network tests require
  explicit authorization; this document does not authorize them.

Detailed policies still to specify before implementation: empty-cloud fallback,
missing/default-identity handling, conflict UX, account switching/logout,
recovery after interrupted import and subsequent cloud write-back. These open
details do not reopen the agreed first-launch flow or desktop-parity goal.

## 6. Current evidence and document precedence

As of 2026-10-14, password login works live in Flutter. Version-2 account-key
unwrap is demonstrated offline; item decryption reproduces five bookmarks,
two identities and one config item. This is **not** an integrated importer or
a verified identity-to-server connection flow. Typed decoding, identity-format
compatibility, secure key lifecycle and app persistence still need integration
and verification. Contacts/account chat remain future work.

This document is the source of truth for **product intent**. It supersedes older
planning rules that put every identity import behind a late manual-only gate,
require a preview for every fresh-app import, or make account chat a permanent
non-goal. Protection of existing identities is still required.

Protocol facts and security boundaries remain governed by:

- [Password login](myteamspeak-login-protocol.md).
- [Account-key unwrap](myteamspeak-key-unwrap-protocol.md).
- [Item decryption evidence](myteamspeak-bookmark-decryption-protocol.md).
- [Sync schemas and system A/B boundary](myteamspeak-sync-protocol.md).

The [historical build plan](myteamspeak-build-plan.md) and
[Flutter migration plan](flutter-migration-plan.md) must be interpreted with
this direction; historical milestone labels are not the current product scope.
Future changes to these requirements should be explicit and recorded here.

## 7. Policies decided for the first import (2026-10-14)

- Empty cloud (nothing importable): nothing is stored, setup is not completed,
  no identity is generated; the user can go back and Skip.
- Invalid or unsupported cloud items are skipped and reported by count; valid
  ones are imported. Importing never replaces a stored item: same cloud ID with
  different content is a reported conflict.
- Bookmark references are kept verbatim (absent, empty or opaque) but never used
  to pick an identity. Each imported bookmark asks the user once; the answer is a
  local link. The `is_default` flag is stored, not used.
- A new local identity is created only by an explicit user choice.
