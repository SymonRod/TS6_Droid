import 'dart:async';

import 'package:ts6_flutter/src/data/account_vault.dart';
import 'package:ts6_flutter/src/data/stores.dart';
import 'package:ts6_flutter/src/myts/session_store.dart';
import 'package:ts6_flutter/src/myts/controller.dart';
import 'package:ts6_flutter/src/rust/api.dart';
import 'package:ts6_flutter/src/state/server_controller.dart';

class StubIdentity implements TsIdentity {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A local identity that only knows its UID (enough for duplicate checks).
class UidIdentity implements TsIdentity {
  final String uid;
  UidIdentity(this.uid);

  @override
  String uniqueId() => uid;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestIdentityStore extends IdentityStore {
  bool present = false;
  String localUid = 'synthetic-local-uid';
  bool readFails = false;
  bool createFails = false;
  int creates = 0;
  int requests = 0;
  Completer<void>? creationGate;
  Completer<void>? inspectionGate;

  @override
  Future<bool> hasIdentity() async {
    await inspectionGate?.future;
    if (readFails) throw StateError('Synthetic unreadable identity');
    return present;
  }

  @override
  Future<TsIdentity?> loadExisting() async {
    await inspectionGate?.future;
    if (readFails) throw StateError('Synthetic unreadable identity');
    return present ? UidIdentity(localUid) : null;
  }

  @override
  Future<TsIdentity> create() async {
    requests++;
    if (createFails) throw StateError('Synthetic storage failure');
    if (present) throw StateError('Identity file already exists');
    creates++;
    present = true;
    return UidIdentity(localUid);
  }

  @override
  Future<TsIdentity> getOrCreate() async {
    requests++;
    await creationGate?.future;
    if (createFails) throw StateError('Synthetic storage failure');
    if (!present) creates++;
    present = true;
    return StubIdentity();
  }
}

class TestServerController extends ServerController {
  @override
  ServerState build() => const ServerState();
}

class TestMyTsController extends MyTsController {
  final MyTsState initial;
  MyTsState loginResult;
  int loginCalls = 0;

  TestMyTsController({
    this.initial = const MyTsState(),
    this.loginResult = const MyTsState(
      status: MyTsStatus.signedIn,
      username: 'Synthetic user',
    ),
  });

  @override
  MyTsState build() => initial;

  @override
  Future<void> login(String rawEmail, String password, {String? otp}) async {
    loginCalls++;
    state = loginResult;
  }

  @override
  Future<void> logout() async => state = const MyTsState();
}

AccountVault memoryVault([MemoryMyTsSecureBackend? backend]) =>
    AccountVault(backend ?? MemoryMyTsSecureBackend());
