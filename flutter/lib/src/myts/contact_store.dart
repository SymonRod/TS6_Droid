import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'session_store.dart';

class StoredContact {
  final String identifier;
  final String note;
  final String matrixId;
  const StoredContact(this.identifier, this.note, this.matrixId);
}

class ContactSnapshot {
  final List<StoredContact> contacts;
  final String? chatHost;
  const ContactSnapshot(this.contacts, this.chatHost);
}

/// Account-scoped secure snapshot. A failed refresh never destroys the last
/// known roster. No Matrix password, signed URL, or avatar bytes are persisted.
class ContactStore {
  final MyTsSecureBackend backend;
  ContactStore([MyTsSecureBackend? backend])
    : backend = backend ?? const FlutterMyTsSecureBackend();

  String _key(String email) =>
      'myts_contacts_${sha256.convert(utf8.encode(email.trim().toLowerCase()))}';

  Future<ContactSnapshot?> load(String email) async {
    final raw = await backend.read(_key(email));
    if (raw == null) return null;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    if (data['owner'] != email.trim().toLowerCase() || data['version'] != 1) {
      throw const FormatException('contact store owner mismatch');
    }
    final contacts = (data['contacts'] as List)
        .map((c) {
          final item = c as List;
          return StoredContact(
            item[0] as String,
            item[1] as String,
            item[2] as String,
          );
        })
        .toList(growable: false);
    if (contacts.length > 512) {
      throw const FormatException('contact store limit');
    }
    return ContactSnapshot(contacts, data['chatHost'] as String?);
  }

  Future<void> save(String email, ContactSnapshot snapshot) async {
    if (snapshot.contacts.length > 512) {
      throw const FormatException('contact store limit');
    }
    // Never replace an unreadable snapshot as though it were absent.
    await load(email);
    await backend.write(
      _key(email),
      jsonEncode({
        'version': 1,
        'owner': email.trim().toLowerCase(),
        'chatHost': snapshot.chatHost,
        'contacts': snapshot.contacts
            .map((c) => [c.identifier, c.note, c.matrixId])
            .toList(),
      }),
    );
  }
}

final contactStoreProvider = Provider<ContactStore>((_) => ContactStore());
