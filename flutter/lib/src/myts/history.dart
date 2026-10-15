import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../rust/myts.dart' as rs;
import 'api.dart';
import 'public_https.dart';
import 'session_store.dart';

/// One account's authenticated-encrypted Rust snapshot, additionally protected by
/// platform secure storage. Never put this in preferences or a shared cache.
class HistoryStore {
  final MyTsSecureBackend backend;
  HistoryStore([MyTsSecureBackend? backend])
    : backend = backend ?? const FlutterMyTsSecureBackend();

  String _key(String account) {
    if (account.isEmpty) throw const FormatException('missing history owner');
    return 'myts_history_v1_${sha256.convert(utf8.encode(account))}';
  }

  Future<Uint8List> load(String account) async {
    final raw = await backend.read(_key(account));
    if (raw == null) return Uint8List(0);
    if (raw.isEmpty || raw.length > 12 * 1024 * 1024) {
      throw const FormatException('invalid history storage');
    }
    return base64Decode(raw);
  }

  Future<void> save(String account, Uint8List snapshot) async {
    if (snapshot.isEmpty || snapshot.length > 8 * 1024 * 1024) {
      throw const FormatException('invalid history snapshot');
    }
    // A single replacement contains token, receive keys, events and replay state.
    await backend.write(_key(account), base64Encode(snapshot));
  }
}

/// Receive-only reader. The Matrix login is explicit, its device intent is saved
/// before POST, and an uncertain outcome never silently creates another device.
class HistoryReader {
  final MyTsApi api;
  final MyTsSessionStore sessions;
  final HistoryStore store;
  final MyTsStoredSession owner;
  final rs.MyTsAccountKey _key;
  final rs.MyTsHistory _history;
  bool _closed = false;

  HistoryReader._(
    this.api,
    this.sessions,
    this.store,
    this.owner,
    this._key,
    this._history,
  );

  static Future<HistoryReader> open({
    required MyTsApi api,
    required MyTsSessionStore sessions,
    required String password,
    bool allowOwnEmpty = false,
    HistoryStore? store,
  }) async {
    final owner = await sessions.load();
    if (owner == null || owner.uuid.isEmpty) {
      throw const FormatException('history account unavailable');
    }
    final key = await api.unlockAccountKey(
      email: owner.email,
      password: password,
      wrappedKey: owner.wrappedKey,
    );
    if (key == null) throw const FormatException('history unlock failed');
    final storage = store ?? HistoryStore();
    try {
      final snapshot = await storage.load(owner.uuid);
      final config = await api.historyConfig(owner.session);
      final history = await rs.myTsHistoryOpen(
        key: key,
        account: owner.uuid,
        configBody: config,
        snapshot: snapshot,
        allowOwnEmpty: allowOwnEmpty,
      );
      final reader = HistoryReader._(
        api,
        sessions,
        storage,
        owner,
        key,
        history,
      );
      try {
        await reader._ensureCurrent();
        await reader._save();
        return reader;
      } catch (_) {
        history.dispose();
        rethrow;
      }
    } catch (_) {
      key.dispose();
      rethrow;
    }
  }

  Future<void> _ensureCurrent() async {
    final current = await sessions.load();
    if (_closed ||
        current?.uuid != owner.uuid ||
        current?.session != owner.session) {
      throw const FormatException('history account changed');
    }
  }

  Future<void> _save() async {
    await _ensureCurrent();
    await store.save(
      owner.uuid,
      await rs.myTsHistorySnapshot(history: _history),
    );
  }

  Future<Map<String, dynamic>> view([String room = '']) async {
    await _ensureCurrent();
    final view =
        jsonDecode(await rs.myTsHistoryView(history: _history, room: room))
            as Map<String, dynamic>;
    // Commit replay bookkeeping before showing newly decrypted messages.
    await _save();
    return view;
  }

  Future<void> _exchange(
    String action, {
    String room = '',
    bool older = false,
  }) async {
    await _ensureCurrent();
    final request = await rs.myTsHistoryRequest(
      history: _history,
      action: action,
      room: room,
      older: older,
    );
    if (action == 'login') await _save();
    final response = await matrixHistoryExchange(request, action, room);
    await _ensureCurrent();
    if (response.status != 200) {
      // A failed/expired stored token is not permission for another Matrix login.
      throw const HttpException('history request failed');
    }
    await rs.myTsHistoryAccept(
      history: _history,
      action: action,
      room: room,
      older: older,
      body: response.body,
    );
    await _save();
  }

  Future<void> connect() async {
    final current = await view();
    if (current['authenticated'] != true) await _exchange('login');
    await refreshRooms();
  }

  Future<void> refreshRooms() async {
    await _exchange('whoami');
    await _exchange('rooms');
    final current = await view();
    // Names are optional: a state fetch failure must not hide a cached room.
    for (final r in (current['rooms'] as List).take(30)) {
      try {
        await _exchange('state', room: r['id'] as String);
      } catch (_) {
        /* Keep cached name. */
      }
    }
  }

  Future<void> messages(String room, {bool older = false}) async {
    await _exchange('messages', room: room, older: older);
    final current = await view(room);
    // Bounded recovery, one exact pair per request, no enumeration or retries.
    for (final session in (current['missing'] as List).take(12)) {
      await _ensureCurrent();
      try {
        final request = await rs.myTsHistoryCloudRequest(
          history: _history,
          session: owner.session,
          room: room,
          groupSession: session as String,
        );
        final response = await api.historyCloud(request);
        await _ensureCurrent();
        await rs.myTsHistoryAcceptCloud(
          history: _history,
          key: _key,
          room: room,
          groupSession: session,
          body: response,
        );
        await _save();
      } catch (_) {
        // Preserve ciphertext and explicitly show unavailable/unsupported keys.
        // The user can retry manually; no sends, device requests or backup upload.
      }
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _history.dispose();
    _key.dispose();
  }
}

/// The only Matrix operations permitted by this reader. No generic SDK connect
/// routine: those often upload device keys as part of initialization.
Future<MyTsHttpResponse> matrixHistoryExchange(
  rs.MyTsHistoryRequest request,
  String action,
  String room,
) async {
  if (!{'login', 'whoami', 'rooms', 'state', 'messages'}.contains(action) ||
      !safePublicHttpsHost(request.host)) {
    throw const FormatException('invalid history destination');
  }
  final segments = switch (action) {
    'state' || 'messages' => ['_matrix', 'client', 'r0', 'rooms', room, action],
    _ => request.path.split('/').where((s) => s.isNotEmpty).toList(),
  };
  final uri = Uri(
    scheme: 'https',
    host: request.host,
    pathSegments: segments,
    queryParameters: (jsonDecode(request.query) as Map).cast<String, String>(),
  );
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  client.findProxy = (_) => 'DIRECT';
  client.connectionFactory = publicHttpsConnection;
  try {
    return await (() async {
      final outgoing = await client.openUrl(
        action == 'login' ? 'POST' : 'GET',
        uri,
      );
      outgoing.followRedirects = false;
      (jsonDecode(request.headers) as Map).cast<String, String>().forEach(
        outgoing.headers.set,
      );
      if (action == 'login') {
        outgoing.contentLength = request.body.length;
        outgoing.add(request.body);
      }
      final response = await outgoing.close();
      if (response.statusCode != 200) {
        return MyTsHttpResponse(response.statusCode, Uint8List(0));
      }
      const limit = 2 * 1024 * 1024;
      if (response.contentLength > limit) throw const MyTsResponseRejected();
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        if (bytes.length + chunk.length > limit) {
          throw const MyTsResponseRejected();
        }
        bytes.add(chunk);
      }
      return MyTsHttpResponse(200, bytes.takeBytes());
    })().timeout(const Duration(seconds: 25));
  } finally {
    client.close(force: true);
    request.body.fillRange(0, request.body.length, 0);
  }
}
