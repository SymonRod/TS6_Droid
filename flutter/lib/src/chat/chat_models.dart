/// Display models decoded from the Rust engine's JSON view. They hold no secrets.
library;

/// Desktop presence values, shared with the Matrix `status_msg` extension.
/// Not the same enum as the avatar states.
abstract final class PresenceState {
  static const available = 0;
  static const away = 1;
  static const doNotDisturb = 2;
  static const offline = 3;
}

class ChatPresence {
  final int state;
  final String status;
  const ChatPresence(this.state, this.status);

  static const unknown = ChatPresence(PresenceState.offline, '');

  factory ChatPresence.fromJson(Map<String, dynamic> j) => ChatPresence(
    (j['state'] as num?)?.toInt().clamp(0, 3) ?? PresenceState.offline,
    (j['status'] as String?) ?? '',
  );
}

class ChatInvite {
  final String room;
  final String inviter;
  final String name;
  const ChatInvite(this.room, this.inviter, this.name);
}

class ChatRoom {
  final String id;
  final String title;

  /// The single other member of a two-person room, or empty for groups.
  final String peer;

  /// `null` until the room state is known; only `false` allows a plaintext send.
  final bool? encrypted;
  final bool hasOlder;
  final int lastTs;
  final String lastBody;
  final String lastSender;
  final String lastStatus;

  const ChatRoom({
    required this.id,
    required this.title,
    required this.peer,
    required this.encrypted,
    required this.hasOlder,
    required this.lastTs,
    required this.lastBody,
    required this.lastSender,
    required this.lastStatus,
  });

  bool get isDirect => peer.isNotEmpty;

  factory ChatRoom.fromJson(Map<String, dynamic> j) => ChatRoom(
    id: j['id'] as String,
    title: (j['title'] as String?) ?? '',
    peer: (j['peer'] as String?) ?? '',
    encrypted: j['encrypted'] as bool?,
    hasOlder: j['has_older'] == true,
    lastTs: (j['last_ts'] as num?)?.toInt() ?? 0,
    lastBody: (j['last_body'] as String?) ?? '',
    lastSender: (j['last_sender'] as String?) ?? '',
    lastStatus: (j['last_status'] as String?) ?? '',
  );
}

class ChatMessage {
  final String id;
  final String sender;
  final int timestamp;
  final String body;

  /// text, emote, notice, image, file, audio, video, other.
  final String kind;

  /// plaintext, decrypted, missing_key, partial, invalid, unsupported, replay,
  /// redacted.
  final String status;

  const ChatMessage({
    required this.id,
    required this.sender,
    required this.timestamp,
    required this.body,
    required this.kind,
    required this.status,
  });

  bool get readable => status == 'plaintext' || status == 'decrypted';

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    id: j['id'] as String,
    sender: j['sender'] as String,
    timestamp: (j['timestamp'] as num?)?.toInt() ?? 0,
    body: (j['body'] as String?) ?? '',
    kind: (j['kind'] as String?) ?? 'text',
    status: (j['status'] as String?) ?? 'unsupported',
  );
}

/// A message the user sent that the server has not confirmed yet.
class PendingMessage {
  final String txn;
  final String text;
  final bool failed;
  const PendingMessage(this.txn, this.text, {this.failed = false});

  PendingMessage copyWith({bool? failed}) =>
      PendingMessage(txn, text, failed: failed ?? this.failed);
}

class ChatAccount {
  final String user;
  final String host;
  final ChatPresence me;
  final Map<String, ChatPresence> presence;
  final Map<String, String> names;
  final Map<String, ChatInvite> invites;

  /// Peer Matrix ID -> direct rooms (`m.direct`).
  final Map<String, List<String>> direct;

  const ChatAccount({
    this.user = '',
    this.host = '',
    this.me = ChatPresence.unknown,
    this.presence = const {},
    this.names = const {},
    this.invites = const {},
    this.direct = const {},
  });

  /// Display name if known, else the Matrix ID's localpart is never guessed:
  /// the full ID is the honest fallback.
  String nameOf(String matrixId) => names[matrixId] ?? matrixId;

  ChatPresence presenceOf(String matrixId) =>
      presence[matrixId] ?? ChatPresence.unknown;

  factory ChatAccount.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic> map(Object? v) =>
        (v as Map?)?.cast<String, dynamic>() ?? const {};
    return ChatAccount(
      user: (j['user'] as String?) ?? '',
      host: (j['host'] as String?) ?? '',
      me: ChatPresence.fromJson(map(j['me'])),
      presence: {
        for (final e in map(j['presence']).entries)
          e.key: ChatPresence.fromJson(map(e.value)),
      },
      names: {
        for (final e in map(j['names']).entries) e.key: e.value as String,
      },
      invites: {
        for (final e in map(j['invites']).entries)
          e.key: ChatInvite(
            e.key,
            (map(e.value)['inviter'] as String?) ?? '',
            (map(e.value)['name'] as String?) ?? '',
          ),
      },
      direct: {
        for (final e in map(j['direct']).entries)
          e.key: [for (final r in e.value as List) r as String],
      },
    );
  }
}
