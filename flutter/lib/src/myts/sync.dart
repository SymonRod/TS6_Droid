import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../data/stores.dart';
import '../rust/myts.dart' as rs;
import 'api.dart';
import 'sync_cursors.dart';

/// Feature flag for myTeamSpeak sync write-back. Off until the live
/// validation step: while off, [MyTsSync.pushBookmark]/[pushIdentity] return
/// [SyncPushStatus.disabled] without touching Rust, the network, the cursor
/// store or the account key. Push/pull stay disabled in production builds
/// regardless of the [SettingsStore.myTsSyncEnabled] opt-out.
const myTsSyncPushEnabled = false;

/// Sync class numbers of the push wire format.
const myTsBookmarkClass = 0;
const myTsIdentityClass = 1;

/// Why a sync push produced no accepted cursors. Transport, service and
/// input failures stay distinguishable; none of them carries payload data.
enum SyncPushStatus {
  /// The service accepted the push; cursors were advanced.
  pushed,

  /// The compile-time feature flag is off: nothing was sent.
  disabled,

  /// The account sync opt-out is off: nothing was sent.
  optedOut,

  /// Unusable input (bad session/UUID/version, cursorless push, oversized
  /// blob, encode failure); nothing was sent.
  invalidInput,

  /// `COLLISION` (303): the server copy wins. Surfaced, never auto-merged;
  /// cursors are untouched.
  conflict,

  /// The service no longer accepts the session: sign in again.
  sessionExpired,

  /// Any other service status (`serverStatus` is set).
  server,

  /// HTTP status != 200 (`httpStatus` is set).
  http,

  /// Malformed or inconsistent reply.
  invalid,

  /// The reply exceeded the receive cap.
  tooLarge,

  /// TLS, DNS, connection or timeout failure.
  network,
}

class SyncPushResult {
  final SyncCursors? cursors;
  final SyncPushStatus? failure;
  final int? httpStatus;
  final int? serverStatus;

  const SyncPushResult.ok(SyncCursors this.cursors)
    : failure = null,
      httpStatus = null,
      serverStatus = null;

  const SyncPushResult.fail(
    SyncPushStatus this.failure, {
    this.httpStatus,
    this.serverStatus,
  }) : cursors = null;

  bool get isOk => cursors != null;
}

/// One bookmark change to push: FULL cloud content plus a bumped outer
/// `item_version`.
///
/// The content must be a complete record (every cloud field the decoder
/// knows), never a lossy subset: the encoder drops unknown fields, so
/// pushing a subset would wipe the omitted fields server-side. Today's
/// vault/cloud bookmark structs are subsets and cannot be used here; the
/// production source will be fresh-pull full records merged with local
/// edits (a step-3 prerequisite recorded in the write-back plan).
///
/// [itemVersion] is opaque to the service but must differ from the stored
/// one; the desktop bumping scheme is unproven, so pushes use a fresh random
/// ID until live evidence says otherwise (see [newItemVersion]). [metadata]
/// fields pass through verbatim; `manipulated` semantics beyond the delete
/// marker (2) are unproven — pass explicitly, never assume.
class SyncPushBookmark {
  final String itemUuid;
  final String itemVersion;
  final rs.MyTsBookmarkContent content;
  final rs.MyTsItemMetadata metadata;

  const SyncPushBookmark({
    required this.itemUuid,
    required this.itemVersion,
    required this.content,
    required this.metadata,
  });
}

/// One identity change to push. Same provenance rules as [SyncPushBookmark];
/// `uniqueIdentity` must be strict-validated desktop material (as stored in
/// the vault), never generated or repaired here.
class SyncPushIdentity {
  final String itemUuid;
  final String itemVersion;
  final rs.MyTsIdentityContent content;
  final rs.MyTsItemMetadata metadata;

  const SyncPushIdentity({
    required this.itemUuid,
    required this.itemVersion,
    required this.content,
    required this.metadata,
  });
}

/// Fresh random outer item version for a push (provisional scheme, see
/// [SyncPushBookmark]).
String newItemVersion() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Gated myTeamSpeak sync write-back: one bookmark or identity change per
/// call, cursors advanced only on `IN_SYNC`.
///
/// Order of checks: feature flag (no I/O at all), account opt-out (no
/// network, no key use), stored cursors (no cursors, no push), then the
/// encode/encrypt/build pipeline in Rust and a single POST with the pull
/// transport policy. Every failure below the flag leaves cursors untouched.
class MyTsSync {
  final MyTsApi _api;
  final SettingsStore _settings;
  final SyncCursorStore _cursors;

  /// Compile-time gate (defaults to [myTsSyncPushEnabled]). Injectable so
  /// tests can exercise the enabled path while production stays disabled.
  final bool pushEnabled;

  MyTsSync({
    MyTsApi? api,
    SettingsStore? settings,
    SyncCursorStore? cursors,
    this.pushEnabled = myTsSyncPushEnabled,
  }) : _api = api ?? MyTsApi(),
       _settings = settings ?? SettingsStore(),
       _cursors = cursors ?? SyncCursorStore();

  Future<SyncPushResult> pushBookmark({
    required String owner,
    required String session,
    required rs.MyTsAccountKey key,
    required SyncPushBookmark item,
  }) => _push(
    owner: owner,
    session: session,
    key: key,
    classNumber: myTsBookmarkClass,
    contentField: 16,
    itemUuid: item.itemUuid,
    itemVersion: item.itemVersion,
    metadata: item.metadata,
    encode: () => rs.myTsEncodeBookmarkContent(content: item.content),
  );

  Future<SyncPushResult> pushIdentity({
    required String owner,
    required String session,
    required rs.MyTsAccountKey key,
    required SyncPushIdentity item,
  }) => _push(
    owner: owner,
    session: session,
    key: key,
    classNumber: myTsIdentityClass,
    contentField: 17,
    itemUuid: item.itemUuid,
    itemVersion: item.itemVersion,
    metadata: item.metadata,
    encode: () => rs.myTsEncodeIdentityContent(content: item.content),
  );

  Future<SyncPushResult> _push({
    required String owner,
    required String session,
    required rs.MyTsAccountKey key,
    required int classNumber,
    required int contentField,
    required String itemUuid,
    required String itemVersion,
    required rs.MyTsItemMetadata metadata,
    required Uint8List? Function() encode,
  }) async {
    if (!pushEnabled) return const SyncPushResult.fail(SyncPushStatus.disabled);
    if (!await _settings.myTsSyncEnabled()) {
      return const SyncPushResult.fail(SyncPushStatus.optedOut);
    }
    if (session.isEmpty || itemUuid.isEmpty || itemVersion.isEmpty) {
      return const SyncPushResult.fail(SyncPushStatus.invalidInput);
    }
    final stored = await _cursors.load(owner);
    final classVersion = stored?.classVersions[classNumber];
    if (stored == null || classVersion == null) {
      // No push without last-known cursors: pull (and store its cursors) first.
      return const SyncPushResult.fail(SyncPushStatus.invalidInput);
    }
    final content = encode();
    if (content == null) {
      return const SyncPushResult.fail(SyncPushStatus.invalidInput);
    }
    final plain = rs.myTsEncodeItemData(
      itemUuid: itemUuid,
      metadata: metadata,
      contentField: contentField,
      content: content,
    );
    if (plain == null) {
      return const SyncPushResult.fail(SyncPushStatus.invalidInput);
    }
    final iv = Uint8List(16);
    _fillSecure(iv);
    final blob = await rs.myTsEncryptItem(key: key, plain: plain, iv: iv);
    _clear(iv);
    if (blob == null) {
      return const SyncPushResult.fail(SyncPushStatus.invalidInput);
    }
    final request = rs.myTsBuildSyncPush(
      session: session,
      globalVersion: stored.globalVersion,
      classes: [
        for (final e in stored.classVersions.entries)
          rs.MyTsClassVersion(
            class_: e.key == myTsIdentityClass
                ? rs.MyTsSyncClass.identity
                : rs.MyTsSyncClass.bookmark,
            version: e.value,
          ),
      ],
      changes: [
        rs.MyTsPushChange(
          class_: classNumber == myTsIdentityClass
              ? rs.MyTsSyncClass.identity
              : rs.MyTsSyncClass.bookmark,
          itemUuid: itemUuid,
          itemVersion: itemVersion,
          blob: blob,
        ),
      ],
    );
    if (request == null) {
      return const SyncPushResult.fail(SyncPushStatus.invalidInput);
    }
    final MyTsHttpResponse resp;
    try {
      resp = await _api.postSyncPush(request);
    } on MyTsResponseRejected {
      return const SyncPushResult.fail(SyncPushStatus.tooLarge);
    } on TimeoutException catch (_) {
      return const SyncPushResult.fail(SyncPushStatus.network);
    } on SocketException catch (_) {
      return const SyncPushResult.fail(SyncPushStatus.network);
    } on HttpException catch (_) {
      return const SyncPushResult.fail(SyncPushStatus.network);
    } on TlsException catch (_) {
      return const SyncPushResult.fail(SyncPushStatus.network);
    }
    final parsed = rs.myTsParseSyncPush(
      httpStatus: resp.status,
      body: resp.body,
    );
    final accepted = parsed.accepted;
    if (accepted != null) {
      final next = SyncCursors(
        globalVersion: accepted.globalVersion,
        classVersions: {
          for (final c in accepted.classes) c.classNumber: c.version,
        },
        itemVersions: {...stored.itemVersions, itemUuid: itemVersion},
      );
      await _cursors.save(owner, next);
      return SyncPushResult.ok(next);
    }
    return SyncPushResult.fail(
      switch (parsed.failure) {
        rs.MyTsPushFailure.http => SyncPushStatus.http,
        rs.MyTsPushFailure.sessionExpired => SyncPushStatus.sessionExpired,
        rs.MyTsPushFailure.server => parsed.serverStatus == 303
            ? SyncPushStatus.conflict
            : SyncPushStatus.server,
        rs.MyTsPushFailure.limit => SyncPushStatus.tooLarge,
        rs.MyTsPushFailure.invalid || null => SyncPushStatus.invalid,
      },
      httpStatus: parsed.httpStatus,
      serverStatus: parsed.serverStatus,
    );
  }

  void _fillSecure(Uint8List iv) {
    final random = Random.secure();
    for (var i = 0; i < iv.length; i++) {
      iv[i] = random.nextInt(256);
    }
  }

  void _clear(Uint8List bytes) {
    bytes.fillRange(0, bytes.length, 0);
  }
}
