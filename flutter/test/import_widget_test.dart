// UI of the account import and of the identity choice before connecting.
// The import controller and resolver are replaced by recording fakes: their
// logic is covered by import_flow_test.dart and identity_resolver_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ts6_flutter/l10n/app_localizations.dart';
import 'package:ts6_flutter/main.dart';
import 'package:ts6_flutter/src/data/account_vault.dart';
import 'package:ts6_flutter/src/data/import_plan.dart';
import 'package:ts6_flutter/src/data/server_bookmark.dart';
import 'package:ts6_flutter/src/myts/controller.dart';
import 'package:ts6_flutter/src/myts/import_controller.dart';
import 'package:ts6_flutter/src/myts/session_store.dart';
import 'package:ts6_flutter/src/ui/chat/chat_screen.dart';
import 'package:ts6_flutter/src/ui/myts_login_screen.dart';
import 'package:ts6_flutter/src/rust/api.dart';
import 'package:ts6_flutter/src/state/identity_resolver.dart';
import 'package:ts6_flutter/src/state/imported_bookmarks.dart';
import 'package:ts6_flutter/src/state/server_controller.dart';
import 'package:ts6_flutter/src/ui/connection_screen.dart';

import 'onboarding_helpers.dart';

class FakeImport extends MyTsImportController {
  final ImportState initial;
  final calls = <String>[];
  FakeImport(this.initial);

  @override
  ImportState build() => initial;

  @override
  Future<void> startFromStoredSession(String password, {bool fromSaved = false}) async =>
      calls.add('start:$password');

  @override
  Future<void> startFromSavedPassword() async => calls.add('start-saved');

  @override
  Future<void> confirm() async => calls.add('confirm');

  @override
  void cancel() => calls.add('cancel');
}

class FakeResolver extends IdentityResolver {
  FakeResolver() : super(vault: AccountVault(), legacy: IdentityStore0());
  ResolvedIdentity? result;
  List<IdentityOption>? offer;
  String? chosen;
  final resolved = <ServerBookmark>[];
  final interactiveFlags = <bool>[];

  @override
  Future<ResolvedIdentity?> resolve(
    ServerBookmark bookmark, {
    required Future<String?> Function(List<IdentityOption>, {required bool canCreate}) ask,
    bool interactive = true,
  }) async {
    resolved.add(bookmark);
    interactiveFlags.add(interactive);
    final options = offer;
    if (options != null) chosen = await ask(options, canCreate: false);
    return chosen == null && offer != null ? null : result;
  }
}

class IdentityStore0 extends TestIdentityStore {}

class RecordingServer extends TestServerController {
  final connects = <(ServerBookmark, TsIdentity)>[];

  @override
  Future<bool> connect(ServerBookmark b, {required TsIdentity identity}) async {
    connects.add((b, identity));
    return true;
  }
}

ImportedBookmark importedEntry({String nickname = 'Me', String? label}) => ImportedBookmark(
  ServerBookmark(
    name: 'Server Three',
    address: 'three.example.invalid',
    nickname: nickname,
    vaultId: 'b-1',
  ),
  identityLabel: label,
);

Future<(ProviderContainer, FakeImport?, FakeResolver, RecordingServer)> mount(
  WidgetTester tester, {
  ImportState importState = const ImportState(),
  List<ImportedBookmark> imported = const [],
  bool setupDone = true,
  MyTsSessionStore? sessions,
  bool signedIn = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final identities = TestIdentityStore()..present = setupDone;
  final import = FakeImport(importState);
  final resolver = FakeResolver();
  final server = RecordingServer();
  final c = ProviderContainer(
    overrides: [
      myTsSessionStoreProvider.overrideWithValue(
        sessions ?? MyTsSessionStore(MemoryMyTsSecureBackend()),
      ),
      identityStoreProvider.overrideWithValue(identities),
      accountVaultProvider.overrideWithValue(memoryVault()),
      serverProvider.overrideWith(() => server),
      myTsProvider.overrideWith(
        () => TestMyTsController(
          initial: MyTsState(
            status: signedIn ? MyTsStatus.signedIn : MyTsStatus.signedOut,
            username: 'Synthetic user',
          ),
        ),
      ),
      myTsImportProvider.overrideWith(() => import),
      identityResolverProvider.overrideWithValue(resolver),
      importedBookmarksProvider.overrideWith((_) async => imported),
    ],
  );
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          routerConfig: ref.watch(routerProvider),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (c, import, resolver, server);
}

Future<void> openAccountScreen(WidgetTester tester, ProviderContainer c) async {
  c.read(routerProvider).go('/myts');
  await tester.pumpAndSettle();
}

void main() {
  group('account import card', () {
    testWidgets('idle: asks for the password and starts an import, clearing the field', (tester) async {
      final (c, import, _, _) = await mount(tester);
      await openAccountScreen(tester, c);
      expect(find.text('Import your account data'), findsOneWidget);
      await tester.tap(find.text('Import account data'));
      await tester.pumpAndSettle();
      expect(import!.calls, isEmpty, reason: 'an empty password does nothing');
      await tester.enterText(find.byType(TextField).first, 'synthetic-password');
      await tester.tap(find.text('Import account data'));
      await tester.pumpAndSettle();
      expect(import.calls, ['start:synthetic-password']);
      expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, isEmpty);
    });

    testWidgets('with a saved password no field is shown and the import starts directly', (tester) async {
      final sessions = MyTsSessionStore(MemoryMyTsSecureBackend());
      await sessions.savePassword('synthetic-password');
      final (c, import, _, _) = await mount(tester, sessions: sessions);
      await openAccountScreen(tester, c);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('The password saved on this device will be used.'), findsOneWidget);
      await tester.tap(find.text('Import account data'));
      await tester.pumpAndSettle();
      expect(import!.calls, ['start-saved']);
    });

    testWidgets('working shows progress', (tester) async {
      final (c, _, _, _) = await mount(tester, importState: const ImportState(phase: ImportPhase.working));
      c.read(routerProvider).go('/myts');
      await tester.pump(); // the spinner never settles
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Downloading and checking your account data…'), findsOneWidget);
    });

    testWidgets('existing data: nothing happens until the user confirms', (tester) async {
      final (c, import, _, _) = await mount(
        tester,
        importState: const ImportState(
          phase: ImportPhase.awaitingConfirmation,
          report: ImportReport(addedIdentities: 2, addedBookmarks: 3, conflictBookmarks: 1),
        ),
      );
      await openAccountScreen(tester, c);
      expect(find.text('Add your account data to this device?'), findsOneWidget);
      expect(find.text('Added 2 identities and 3 bookmarks.'), findsOneWidget);
      expect(find.textContaining('Skipped 1 items'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(import!.calls, ['cancel', 'confirm']);
    });

    testWidgets('done: summary, then continue to the connection screen', (tester) async {
      final (c, _, _, _) = await mount(
        tester,
        importState: const ImportState(
          phase: ImportPhase.done,
          report: ImportReport(addedIdentities: 2, addedBookmarks: 3),
        ),
      );
      await openAccountScreen(tester, c);
      expect(find.text('Added 2 identities and 3 bookmarks.'), findsOneWidget);
      expect(find.textContaining('choose which identity each bookmark uses'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectionScreen), findsOneWidget);
    });

    testWidgets('already up to date', (tester) async {
      final (c, _, _, _) = await mount(
        tester,
        importState: const ImportState(phase: ImportPhase.done, report: ImportReport(unchangedBookmarks: 3)),
      );
      await openAccountScreen(tester, c);
      expect(find.textContaining('already on this device. Nothing was changed.'), findsOneWidget);
    });

    testWidgets('empty cloud: explained, nothing completes', (tester) async {
      final (c, _, _, _) = await mount(
        tester,
        importState: const ImportState(phase: ImportPhase.nothingToImport, report: ImportReport(cloudEmpty: true)),
      );
      await openAccountScreen(tester, c);
      expect(find.textContaining('no identities or bookmarks to import'), findsOneWidget);
    });

    for (final (failure, text) in [
      (ImportFailure.unlock, 'could not be unlocked'),
      (ImportFailure.network, 'Network error'),
      (ImportFailure.sessionExpired, 'sign-in expired'),
      (ImportFailure.integrity, 'integrity check'),
      (ImportFailure.storage, 'Nothing existing was replaced'),
    ]) {
      testWidgets('failure $failure is explained and can be retried', (tester) async {
        final (c, import, _, _) = await mount(
          tester,
          importState: ImportState(phase: ImportPhase.failed, failure: failure),
        );
        await openAccountScreen(tester, c);
        expect(find.textContaining(text), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, 'pw');
        await tester.tap(find.text('Import account data'));
        await tester.pumpAndSettle();
        expect(import!.calls, ['start:pw']);
      });
    }
  });

  group('connection list and identity choice', () {
    testWidgets('imported bookmarks are listed with their identity state', (tester) async {
      await mount(tester, imported: [importedEntry(), importedEntry(label: 'Alice')]);
      expect(find.text('Server Three'), findsNWidgets(2));
      expect(find.textContaining('From your account · Identity: not chosen yet'), findsOneWidget);
      expect(find.textContaining('From your account · Identity: Alice'), findsOneWidget);
      expect(find.text('No saved bookmarks yet'), findsNothing);
    });

    testWidgets('home page has a visible chat entry that opens the chat', (tester) async {
      await mount(tester);
      expect(find.text('Account chat'), findsOneWidget);
      expect(find.text('Conversations and contacts'), findsOneWidget);
      await tester.tap(find.text('Account chat'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsOneWidget);
    });

    testWidgets('signed out, the home chat entry leads to the sign-in', (tester) async {
      await mount(tester, signedIn: false);
      expect(find.text('Sign in with myTeamSpeak to chat with your contacts'), findsOneWidget);
      await tester.tap(find.text('Account chat'));
      await tester.pumpAndSettle();
      expect(find.byType(MyTsLoginScreen), findsOneWidget);
    });

    testWidgets('no choice, no connection', (tester) async {
      final (_, _, resolver, server) = await mount(tester, imported: [importedEntry()]);
      await tester.tap(find.text('Server Three'));
      await tester.pumpAndSettle();
      expect(resolver.resolved.single.vaultId, 'b-1');
      expect(server.connects, isEmpty);
    });

    testWidgets('the chooser lists identities, preselects none, and its answer is used', (tester) async {
      final (_, _, resolver, server) = await mount(tester, imported: [importedEntry()]);
      resolver.offer = const [
        IdentityOption(id: 'i-a', label: 'Alice', uid: 'uid-aaaa'),
        IdentityOption(id: 'i-b', label: 'Bob', uid: 'uid-bbbb'),
      ];
      final identity = StubIdentity();
      resolver.result = ResolvedIdentity(identity, null);
      await tester.tap(find.text('Server Three'));
      await tester.pumpAndSettle();
      expect(find.text('Choose an identity'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('uid-bbbb'), findsOneWidget);
      expect(find.byType(RadioListTile<String>), findsNothing);
      await tester.tap(find.text('Bob'));
      await tester.pumpAndSettle();
      expect(resolver.chosen, 'i-b');
      expect(server.connects.single.$2, same(identity));
      expect(server.connects.single.$1.address, 'three.example.invalid');
    });

    testWidgets('cancelling the chooser does not connect', (tester) async {
      final (_, _, resolver, server) = await mount(tester, imported: [importedEntry()]);
      resolver.offer = const [IdentityOption(id: 'i-a', label: 'Alice', uid: 'uid-aaaa')];
      await tester.tap(find.text('Server Three'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(server.connects, isEmpty);
    });

    testWidgets('a bookmark without nickname uses the identity nickname', (tester) async {
      final (_, _, resolver, server) = await mount(tester, imported: [importedEntry(nickname: '')]);
      resolver.result = ResolvedIdentity(StubIdentity(), 'Alice');
      await tester.tap(find.text('Server Three'));
      await tester.pumpAndSettle();
      expect(server.connects.single.$1.nickname, 'Alice');
    });

    testWidgets('no nickname anywhere: asks for one instead of connecting', (tester) async {
      final (_, _, resolver, server) = await mount(tester, imported: [importedEntry(nickname: '')]);
      resolver.result = ResolvedIdentity(StubIdentity(), null);
      await tester.tap(find.text('Server Three'));
      await tester.pumpAndSettle();
      expect(server.connects, isEmpty);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('own bookmarks and manual addresses go through the same resolver', (tester) async {
      final (_, _, resolver, server) = await mount(tester);
      resolver.result = ResolvedIdentity(StubIdentity(), null);
      await tester.tap(find.text('New server'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'manual.example.invalid');
      await tester.enterText(find.byType(TextField).at(1), 'Me');
      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await tester.pumpAndSettle();
      expect(resolver.resolved.single.vaultId, isNull);
      expect(server.connects.single.$1.address, 'manual.example.invalid');
    });
  });
}
