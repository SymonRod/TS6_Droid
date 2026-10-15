import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ts6_flutter/l10n/app_localizations.dart';
import 'package:ts6_flutter/src/myts/history.dart';
import 'package:ts6_flutter/src/myts/session_store.dart';
import 'package:ts6_flutter/src/rust/myts.dart' as rs;
import 'package:ts6_flutter/src/ui/myts_history_screen.dart';

import 'myts_rust.dart';

List<int> _varint(int n) {
  final out = <int>[];
  while (n >= 128) {
    out.add((n & 127) | 128);
    n >>= 7;
  }
  return [...out, n];
}

List<int> _field(int n, List<int> data) => [
  ..._varint(n * 8 + 2),
  ..._varint(data.length),
  ...data,
];
Uint8List _bytes(Object value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));
Uint8List _hex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);

void main() {
  setUpAll(initRustForTests);

  test(
    'opaque reader decrypts independent libolm fixture across sealed restart',
    () async {
      final fixture =
          jsonDecode(
                await File(
                  Platform.environment['TSLIB_HISTORY_FIXTURE']!,
                ).readAsString(),
              )
              as Map;
      final key = await rs.myTsUnlockAccountKey(
        email: 'alice@example.com',
        password: 'correct horse battery staple',
        wrappedKey: _hex(
          '02323ec445370cb098574647e56416e082000102030405060708090a0bdf3d396ab4b8ccefbfd431d67420448f56791f8f13c313943db655c533aaf63b',
        ),
      );
      addTearDown(key.dispose);
      final h = await rs.myTsHistoryOpen(
        key: key,
        account: 'synthetic-account',
        configBody: base64Decode(fixture['config_reply'] as String),
        snapshot: Uint8List(0),
        allowOwnEmpty: false,
      );
      addTearDown(h.dispose);
      await rs.myTsHistoryAccept(
        history: h,
        action: 'rooms',
        room: '',
        older: false,
        body: _bytes({
          'joined_rooms': [fixture['room']],
        }),
      );
      await rs.myTsHistoryAccept(
        history: h,
        action: 'messages',
        room: fixture['room'] as String,
        older: false,
        body: _bytes({'chunk': fixture['events'], 'end': 'older'}),
      );
      final entry = [
        ..._field(1, utf8.encode(fixture['room'] as String)),
        ..._field(2, utf8.encode(fixture['session'] as String)),
        ..._field(3, utf8.encode(fixture['envelope'] as String)),
      ];
      expect(
        await rs.myTsHistoryAcceptCloud(
          history: h,
          key: key,
          room: fixture['room'] as String,
          groupSession: fixture['session'] as String,
          body: Uint8List.fromList([
            ..._field(1, [8, 1]),
            ..._field(2, entry),
          ]),
        ),
        isTrue,
      );
      final view =
          jsonDecode(
                await rs.myTsHistoryView(
                  history: h,
                  room: fixture['room'] as String,
                ),
              )
              as Map;
      expect((view['messages'] as List).map((m) => m['status']), [
        'partial',
        'partial',
        'partial',
        'decrypted',
        'decrypted',
        'decrypted',
      ]);
      final store = HistoryStore(MemoryMyTsSecureBackend());
      await store.save(
        'synthetic-account',
        await rs.myTsHistorySnapshot(history: h),
      );
      final restored = await rs.myTsHistoryOpen(
        key: key,
        account: 'synthetic-account',
        configBody: base64Decode(fixture['config_reply'] as String),
        snapshot: await store.load('synthetic-account'),
        allowOwnEmpty: false,
      );
      addTearDown(restored.dispose);
      final recovered =
          jsonDecode(
                await rs.myTsHistoryView(
                  history: restored,
                  room: fixture['room'] as String,
                ),
              )
              as Map;
      expect((recovered['messages'] as List)[5]['body'], 'Synthetic message 5');
      expect(await store.load('other-account'), isEmpty);
    },
  );

  testWidgets('history page opens locked without network or Matrix login', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const MyTsHistoryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Unlock history'), findsOneWidget);
    expect(find.text('Connect / refresh conversations'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
