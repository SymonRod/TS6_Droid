// Sync gating basics: compile-time flag, opt-out setting default and fresh
// version IDs. The disabled/opted-out paths (which need an account key and
// therefore the native library) are covered in `myts_sync_push_test.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ts6_flutter/src/data/stores.dart';
import 'package:ts6_flutter/src/myts/sync.dart';

void main() {
  test('push stays behind the compile-time flag', () {
    expect(myTsSyncPushEnabled, isFalse);
  });

  test('sync opt-out defaults to on and round-trips', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsStore();
    expect(await settings.myTsSyncEnabled(), isTrue);
    await settings.setMyTsSyncEnabled(false);
    expect(await settings.myTsSyncEnabled(), isFalse);
    await settings.setMyTsSyncEnabled(true);
    expect(await settings.myTsSyncEnabled(), isTrue);
  });

  test('fresh item versions are 128-bit hex and unique', () {
    final ids = {for (var i = 0; i < 100; i++) newItemVersion()};
    expect(ids.length, 100);
    for (final id in ids) {
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(id), isTrue);
    }
  });
}
