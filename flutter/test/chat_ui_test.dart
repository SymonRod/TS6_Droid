import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ts6_flutter/l10n/app_localizations.dart';
import 'package:ts6_flutter/src/chat/chat_controller.dart';
import 'package:ts6_flutter/src/chat/chat_models.dart';
import 'package:ts6_flutter/src/myts/contact_store.dart';
import 'package:ts6_flutter/src/myts/controller.dart';
import 'package:ts6_flutter/src/myts/session_store.dart';
import 'package:ts6_flutter/src/ui/chat/chat_screen.dart';
import 'package:ts6_flutter/src/ui/chat/conversation_screen.dart';
import 'package:ts6_flutter/src/ui/chat/profile_tab.dart';
import 'package:ts6_flutter/src/ui/theme.dart';

class _SignedIn extends MyTsController {
  @override
  MyTsState build() => const MyTsState(
    status: MyTsStatus.signedIn,
    username: 'alice',
    email: 'alice@example.com',
  );
}

class _FakeChat extends ChatController {
  final ChatState initial;
  final sent = <(String, String)>[];
  final unlocked = <String>[];
  int savedAttempts = 0;
  final savedContacts = <(String, String)>[];

  /// What [needsEncryptionConsent] answers; [granted] counts agreements.
  bool consentNeeded = false;
  int granted = 0;
  _FakeChat(this.initial);

  void raise(ChatNotice notice) => state = state.copyWith(notice: notice);
  ChatNotice? get currentNotice => state.notice;

  @override
  Future<bool> needsEncryptionConsent(String room) async => consentNeeded;

  @override
  Future<bool> grantEncryptionConsent() async {
    granted++;
    consentNeeded = false;
    return true;
  }

  @override
  ChatState build() => initial;

  @override
  Future<void> openRoom(String room) async {}

  @override
  Future<void> send(String room, String text) async =>
      sent.add((room, text.trim()));

  @override
  Future<void> unlock(
    String password, {
    bool allowOwnEmpty = false,
    bool fromSaved = false,
  }) async => unlocked.add(password);

  @override
  Future<void> unlockWithSaved() async => savedAttempts++;

  @override
  Future<void> refreshContacts() async {}

  @override
  Future<bool> saveContact(String matrixId, String note) async {
    savedContacts.add((matrixId, note));
    return true;
  }
}

const _me = '@alice:example.invalid';
const _friend = '@friend:example.invalid';

ChatState _ready({
  bool encrypted = false,
  String peer = _friend,
  ChatError? error,
  bool friendIsContact = true,
}) => ChatState(
  error: error,
  phase: ChatPhase.ready,
  account: const ChatAccount(
    user: _me,
    me: ChatPresence(PresenceState.away, 'brb'),
    names: {_friend: 'Friendly'},
    presence: {_friend: ChatPresence(PresenceState.available, 'Hello')},
    invites: {'!inv:x': ChatInvite('!inv:x', _friend, 'Game night')},
  ),
  rooms: [
    ChatRoom(
      id: '!room:example.invalid',
      title: 'Friend',
      peer: peer,
      encrypted: encrypted,
      hasOlder: true,
      lastTs: DateTime.now().millisecondsSinceEpoch,
      lastBody: 'see you',
      lastSender: _friend,
      lastStatus: 'plaintext',
    ),
  ],
  messages: {
    '!room:example.invalid': [
      ChatMessage(
        id: r'$1',
        sender: _friend,
        timestamp: DateTime.now().millisecondsSinceEpoch - 60000,
        body: 'see you',
        kind: 'text',
        status: 'plaintext',
      ),
      ChatMessage(
        id: r'$2',
        sender: _me,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        body: 'ok!',
        kind: 'text',
        status: 'plaintext',
      ),
      ChatMessage(
        id: r'$3',
        sender: _friend,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        body: '',
        kind: 'text',
        status: 'missing_key',
      ),
    ],
  },
  contacts: friendIsContact
      ? const [StoredContact('', 'Pal', _friend)]
      : const [],
);

Widget _app(_FakeChat chat, Widget home, {MyTsSessionStore? sessions}) =>
    ProviderScope(
      overrides: [
        myTsSessionStoreProvider.overrideWithValue(
          sessions ?? MyTsSessionStore(MemoryMyTsSecureBackend()),
        ),
        myTsProvider.overrideWith(_SignedIn.new),
        chatProvider.overrideWith(() => chat),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

void main() {
  testWidgets('locked chat asks for the password and shows no conversations', (
    tester,
  ) async {
    final chat = _FakeChat(const ChatState());
    await tester.pumpWidget(_app(chat, const ChatScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Unlock your chat'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.enterText(find.byType(TextField), 'hunter2');
    await tester.tap(find.text('Unlock'));
    await tester.pump();
    expect(chat.unlocked, ['hunter2']);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
      reason: 'the password field is wiped after submit',
    );
  });

  testWidgets(
    'locked chat tries the saved password once and offers the remember option',
    (tester) async {
      final chat = _FakeChat(const ChatState());
      await tester.pumpWidget(_app(chat, const ChatScreen()));
      await tester.pumpAndSettle();
      expect(chat.savedAttempts, 1);
      expect(find.text('Remember password on this device'), findsOneWidget);
    },
  );

  testWidgets(
    'with a saved password the form is replaced by a one-tap unlock',
    (tester) async {
      final sessions = MyTsSessionStore(MemoryMyTsSecureBackend());
      await sessions.savePassword('saved-secret');
      final chat = _FakeChat(const ChatState());
      await tester.pumpWidget(
        _app(chat, const ChatScreen(), sessions: sessions),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(
        find.text('Unlocking with the password saved on this device.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Unlock'));
      await tester.pump();
      expect(chat.savedAttempts, 2, reason: 'automatic attempt plus the tap');
      await tester.tap(find.text('Enter password manually'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    },
  );

  testWidgets('ready chat has chats, contacts and profile tabs', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_FakeChat(_ready()), const ChatScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Friendly'), findsWidgets);
    expect(find.text('see you'), findsOneWidget);
    expect(find.text('Friendly invited you'), findsOneWidget);
    expect(find.text('Game night'), findsOneWidget);

    await tester.tap(find.text('Contacts'));
    await tester.pumpAndSettle();
    expect(find.text('Pal'), findsOneWidget);
    expect(find.text('Available · Hello'), findsOneWidget);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text(_me), findsOneWidget);
    expect(find.text('Do not disturb'), findsOneWidget);
    expect(
      find.textContaining("isn't available in TS6 Droid yet"),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Lock chat'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ProfileTab),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Lock chat'), findsOneWidget);
  });

  testWidgets('a clear conversation sends trimmed text; own bubble right', (
    tester,
  ) async {
    final chat = _FakeChat(_ready());
    await tester.pumpWidget(
      _app(chat, const ConversationScreen(roomId: '!room:example.invalid')),
    );
    await tester.pumpAndSettle();
    expect(find.text('ok!'), findsOneWidget);
    expect(find.text('Encrypted message · key not available'), findsOneWidget);
    expect(find.text('Load older messages'), findsOneWidget);
    expect(find.text('Available · Hello'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  hi there  ');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    expect(chat.sent, [('!room:example.invalid', 'hi there')]);
  });

  testWidgets('a direct chat with a non-contact can add them to the contacts', (
    tester,
  ) async {
    final chat = _FakeChat(_ready(friendIsContact: false));
    await tester.pumpWidget(
      _app(chat, const ConversationScreen(roomId: '!room:example.invalid')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.person_add_alt_1));
    await tester.pumpAndSettle();
    // The id is fixed and the note is prefilled with the conversation title.
    expect(find.widgetWithText(TextField, _friend), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Friendly'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Friendly'), 'Buddy');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(chat.savedContacts, [(_friend, 'Buddy')]);
    expect(find.text('Contact added'), findsOneWidget);
  });

  testWidgets('no add-contact button for someone already a contact', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _FakeChat(_ready()),
        const ConversationScreen(roomId: '!room:example.invalid'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.person_add_alt_1), findsNothing);
  });

  testWidgets('adding a contact from the contacts tab disposes cleanly', (
    tester,
  ) async {
    final chat = _FakeChat(_ready());
    await tester.pumpWidget(_app(chat, const ChatScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contacts'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.person_add_alt_1));
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), '@new:example.invalid');
    await tester.enterText(fields.at(1), 'Newbie');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(chat.savedContacts, [('@new:example.invalid', 'Newbie')]);

    // Cancelling must not trip over the controllers either.
    await tester.tap(find.byIcon(Icons.person_add_alt_1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('an encrypted group is read-only with an explanation', (
    tester,
  ) async {
    final chat = _FakeChat(_ready(encrypted: true, peer: ''));
    await tester.pumpWidget(
      _app(chat, const ConversationScreen(roomId: '!room:example.invalid')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.send), findsNothing);
    expect(
      find.textContaining('only available in one-to-one encrypted'),
      findsOneWidget,
    );
  });

  testWidgets('an encrypted one-to-one conversation can be written to', (
    tester,
  ) async {
    final chat = _FakeChat(_ready(encrypted: true));
    await tester.pumpWidget(
      _app(chat, const ConversationScreen(roomId: '!room:example.invalid')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.textContaining('only available in one-to-one'), findsNothing);
    await tester.enterText(find.byType(TextField), 'secret hi');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing, reason: 'already agreed');
    expect(chat.sent, [('!room:example.invalid', 'secret hi')]);
  });

  testWidgets(
    'declining the encryption consent sends nothing and keeps the text',
    (tester) async {
      final chat = _FakeChat(_ready(encrypted: true))..consentNeeded = true;
      await tester.pumpWidget(
        _app(chat, const ConversationScreen(roomId: '!room:example.invalid')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'secret hi');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      expect(
        find.text('Send encrypted messages from this phone?'),
        findsOneWidget,
      );
      expect(find.textContaining('“TS6 Droid”'), findsOneWidget);
      expect(find.textContaining("haven't been verified"), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(chat.sent, isEmpty);
      expect(chat.granted, 0);
      expect(
        find.text('secret hi'),
        findsOneWidget,
        reason: 'the typed text stays',
      );

      // Agreeing records the consent once and then sends.
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(chat.granted, 1);
      expect(chat.sent, [('!room:example.invalid', 'secret hi')]);
      expect(
        find.text('secret hi'),
        findsNothing,
        reason: 'the field was cleared',
      );

      await tester.enterText(find.byType(TextField), 'and again');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason: 'never asked twice',
      );
      expect(chat.granted, 1);
      expect(chat.sent.last, ('!room:example.invalid', 'and again'));
    },
  );

  for (final (error, text) in [
    (ChatError.noRecipients, 'none of this contact\'s devices'),
    (ChatError.unsupportedRoom, "can't be sent in this conversation yet"),
    (ChatError.limit, "can't hold more encryption sessions"),
  ]) {
    testWidgets('the $error failure explains itself in the banner', (
      tester,
    ) async {
      final chat = _FakeChat(_ready(encrypted: true, error: error));
      await tester.pumpWidget(
        _app(chat, const ConversationScreen(roomId: '!room:example.invalid')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining(text), findsOneWidget);
    });
  }

  testWidgets('a changed contact device is announced once, without blocking', (
    tester,
  ) async {
    final chat = _FakeChat(_ready(encrypted: true));
    await tester.pumpWidget(
      _app(chat, const ConversationScreen(roomId: '!room:example.invalid')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('changed its encryption keys'), findsNothing);
    chat.raise(ChatNotice.deviceChanged);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('changed its encryption keys'), findsOneWidget);
    expect(chat.currentNotice, isNull, reason: 'shown once, then cleared');
    expect(find.byType(TextField), findsOneWidget, reason: 'still writable');
  });
}
