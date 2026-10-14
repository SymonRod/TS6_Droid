// Synthetic native identity/filesystem checks. No account or network access.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ts6_flutter/src/data/onboarding_store.dart';
import 'package:ts6_flutter/src/data/stores.dart';

import 'myts_rust.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initRustForTests);
  late Directory dir;
  late IdentityStore identities;
  late OnboardingStore setup;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('ts6-onboarding-');
    identities = IdentityStore(supportDirectory: () async => dir);
    setup = OnboardingStore(identities: identities, bookmarks: BookmarkStore());
  });
  tearDown(() async => dir.delete(recursive: true));

  test(
    'fresh inspection creates no file; skip saves a reusable native identity',
    () async {
      expect(await setup.isComplete(), false);
      expect(await dir.list().isEmpty, true);
      await setup.skip();
      final file = File('${dir.path}/identity.txt');
      final saved = await file.readAsString();
      final id = await identities.getOrCreate();
      final uid = id.uniqueId();
      expect(uid, isNotEmpty);
      expect(id.exportString(), saved);
      final restarted = IdentityStore(supportDirectory: () async => dir);
      expect(await restarted.hasIdentity(), true);
      await OnboardingStore(
        identities: restarted,
        bookmarks: BookmarkStore(),
      ).skip();
      expect((await restarted.getOrCreate()).uniqueId(), uid);
      expect(await file.readAsString(), saved);
    },
  );

  test(
    'legacy identity without a completion marker is preserved byte-for-byte',
    () async {
      final id = await identities.getOrCreate();
      final saved = await File('${dir.path}/identity.txt').readAsString();
      expect(await setup.isComplete(), true);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          OnboardingStore.completeKey,
        ),
        isNull,
      );
      expect((await identities.getOrCreate()).uniqueId(), id.uniqueId());
      expect(await File('${dir.path}/identity.txt').readAsString(), saved);
    },
  );

  test(
    'corrupt existing identity is never overwritten or classified as empty',
    () async {
      final file = File('${dir.path}/identity.txt');
      await file.writeAsString('synthetic-invalid-identity');
      await expectLater(setup.isComplete(), throwsA(anything));
      await expectLater(setup.skip(), throwsA(anything));
      expect(await file.readAsString(), 'synthetic-invalid-identity');
      expect(
        (await SharedPreferences.getInstance()).getBool(
          OnboardingStore.completeKey,
        ),
        isNull,
      );
    },
  );

  test('storage read failure is not evidence of a fresh app', () async {
    final broken = IdentityStore(
      supportDirectory: () async =>
          throw const FileSystemException('Synthetic failure'),
    );
    await expectLater(
      OnboardingStore(
        identities: broken,
        bookmarks: BookmarkStore(),
      ).isComplete(),
      throwsA(isA<FileSystemException>()),
    );
  });
}
