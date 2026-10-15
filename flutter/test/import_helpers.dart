// Shared fixtures for the account-import flow tests: synthetic transport,
// in-memory secure storage that can fail, and a fully wired container.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ts6_flutter/src/data/account_vault.dart';
import 'package:ts6_flutter/src/myts/api.dart';
import 'package:ts6_flutter/src/myts/controller.dart';
import 'package:ts6_flutter/src/myts/session_store.dart';
import 'package:ts6_flutter/src/myts/sync_cursors.dart';
import 'package:ts6_flutter/src/state/server_controller.dart';

import 'fixtures/synthetic_pull.dart';
import 'myts_helpers.dart';
import 'onboarding_helpers.dart';

/// Memory backend whose writes can be made to fail or to be silently lost.
class FlakyBackend extends MemoryMyTsSecureBackend {
  int writes = 0;
  bool failWrites = false;
  bool dropWrites = false;

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('Synthetic write failure');
    writes++;
    if (dropWrites) return;
    await super.write(key, value);
  }
}

class Call {
  final Uri uri;
  final Map<String, String> headers;
  final Uint8List body;
  final int maxBytes;
  Call(this.uri, this.headers, this.body, this.maxBytes);
}

/// Answers /authentication with a successful login and /synchronization with
/// whatever [sync] returns (or throws).
class FakeService {
  Uint8List loginKey = fixtureWrappedKey;
  Future<MyTsHttpResponse> Function(Call call) sync =
      (_) async => MyTsHttpResponse(200, fixturePullFull);
  final calls = <Call>[];

  Future<MyTsHttpResponse> post(
    Uri uri,
    Map<String, String> headers,
    Uint8List body,
    int maxBytes,
  ) async {
    final call = Call(uri, headers, body, maxBytes);
    calls.add(call);
    if (uri.path == '/authentication') {
      return MyTsHttpResponse(
        200,
        loginSessionReply(
          error: 200,
          session: 'synthetic-session',
          uuid: 'synthetic-account',
          username: 'synthetic-user',
          key: loginKey,
        ),
      );
    }
    return sync(call);
  }

  List<Call> get syncCalls => [for (final c in calls) if (c.uri.path == '/synchronization') c];
}

class World {
  final service = FakeService();
  final identities = TestIdentityStore();
  final sessionBackend = MemoryMyTsSecureBackend();
  final vaultBackend = FlakyBackend();
  final cursorBackend = MemoryMyTsSecureBackend();
  late final ProviderContainer container = build();

  AccountVault get vault => AccountVault(vaultBackend);
  SyncCursorStore get cursors => SyncCursorStore(cursorBackend);

  ProviderContainer build() => ProviderContainer(
    overrides: [
      myTsApiProvider.overrideWithValue(MyTsApi(post: service.post, deviceName: 'Test')),
      myTsSessionStoreProvider.overrideWithValue(MyTsSessionStore(sessionBackend)),
      accountVaultProvider.overrideWithValue(vault),
      syncCursorStoreProvider.overrideWithValue(cursors),
      identityStoreProvider.overrideWithValue(identities),
    ],
  );

  /// A second process start over the same storage.
  ProviderContainer restart() => build();
}
