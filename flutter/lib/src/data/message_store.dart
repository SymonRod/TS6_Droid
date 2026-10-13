import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Chat history kept as one JSON file per server address in the app files dir.
class MessageStore {
  static const maxMessages = 500;

  Future<File> _file(String address) async {
    final dir = await getApplicationSupportDirectory();
    final safe = address.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return File('${dir.path}/chat_$safe.json');
  }

  Future<List<Map<String, dynamic>>> load(String address) async {
    try {
      final f = await _file(address);
      if (!await f.exists()) return [];
      final list = jsonDecode(await f.readAsString()) as List;
      return [for (final j in list) (j as Map).cast<String, dynamic>()];
    } catch (_) {
      return [];
    }
  }

  Future<void> save(String address, List<Map<String, dynamic>> messages) async {
    try {
      final f = await _file(address);
      final tail = messages.length > maxMessages ? messages.sublist(messages.length - maxMessages) : messages;
      await f.writeAsString(jsonEncode(tail));
    } catch (_) {}
  }

  Future<void> clear(String address) async {
    try {
      final f = await _file(address);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
