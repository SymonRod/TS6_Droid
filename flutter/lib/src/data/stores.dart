import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../rust/api.dart';
import 'server_bookmark.dart';

class BookmarkStore {
  static const _kBookmarks = 'bookmarks_json';
  static const _kLast = 'last_bookmark_address';
  static const _kAutoReconnect = 'auto_reconnect';

  /// First setup must distinguish absent data from unreadable saved data.
  /// Unlike [load], this deliberately propagates malformed storage errors.
  Future<bool> hasSavedBookmarks() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kBookmarks);
    if (raw == null) return false;
    final list = jsonDecode(raw) as List;
    for (final item in list) {
      if (item is! Map<String, dynamic> ||
          item['address'] is! String ||
          (item['address'] as String).trim().isEmpty) {
        throw const FormatException('Invalid saved bookmark');
      }
    }
    return list.isNotEmpty;
  }

  Future<List<ServerBookmark>> load() async {
    final p = await SharedPreferences.getInstance();
    try {
      final list = jsonDecode(p.getString(_kBookmarks) ?? '[]') as List;
      return [for (final j in list) ServerBookmark.fromJson(j as Map<String, dynamic>)];
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<ServerBookmark> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kBookmarks, jsonEncode([for (final b in list) b.toJson()]));
  }

  Future<String> lastAddress() async =>
      (await SharedPreferences.getInstance()).getString(_kLast) ?? '';

  Future<void> setLastAddress(String a) async =>
      (await SharedPreferences.getInstance()).setString(_kLast, a);

  Future<bool> autoReconnect() async =>
      (await SharedPreferences.getInstance()).getBool(_kAutoReconnect) ?? false;

  Future<void> setAutoReconnect(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_kAutoReconnect, v);
}

/// Same keys as the Kotlin SettingsStore (audio gain is used from phase 3).
class SettingsStore {
  Future<double> audioGain() async =>
      (await SharedPreferences.getInstance()).getDouble('audio_gain') ?? 1.0;
  Future<void> setAudioGain(double v) async =>
      (await SharedPreferences.getInstance()).setDouble('audio_gain', v);

  Future<bool> pushToTalk() async =>
      (await SharedPreferences.getInstance()).getBool('push_to_talk') ?? false;
  Future<void> setPushToTalk(bool v) async =>
      (await SharedPreferences.getInstance()).setBool('push_to_talk', v);

  Future<bool> showLinkThumbnails() async =>
      (await SharedPreferences.getInstance()).getBool('show_link_thumbnails') ?? false;
  Future<void> setShowLinkThumbnails(bool v) async =>
      (await SharedPreferences.getInstance()).setBool('show_link_thumbnails', v);

  Future<bool> autoLoadImages() async =>
      (await SharedPreferences.getInstance()).getBool('auto_load_images') ?? true;
  Future<void> setAutoLoadImages(bool v) async =>
      (await SharedPreferences.getInstance()).setBool('auto_load_images', v);
}

/// Identity kept as the exported string in the app's files dir.
class IdentityStore {
  final Future<Directory> Function() _supportDirectory;

  IdentityStore({Future<Directory> Function()? supportDirectory})
    : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  /// Inspect without generating an identity. Invalid existing data is an
  /// error, never evidence that the app is empty.
  Future<bool> hasIdentity() async {
    final dir = await _supportDirectory();
    final f = File('${dir.path}/identity.txt');
    if (!await f.exists()) return false;
    await TsIdentity.fromString(data: await f.readAsString());
    return true;
  }

  /// The identity file's identity, or null when there is none. Never creates
  /// anything; unreadable data throws instead of looking absent.
  Future<TsIdentity?> loadExisting() async {
    final dir = await _supportDirectory();
    final f = File('${dir.path}/identity.txt');
    if (!await f.exists()) return null;
    return TsIdentity.fromString(data: await f.readAsString());
  }

  /// Creates the identity file's identity on an explicit user request. Refuses
  /// to touch an existing file.
  Future<TsIdentity> create() async {
    final dir = await _supportDirectory();
    final f = File('${dir.path}/identity.txt');
    if (await f.exists()) throw StateError('Identity file already exists');
    final id = await TsIdentity.create();
    await f.writeAsString(id.exportString());
    return id;
  }

  Future<TsIdentity> getOrCreate() async {
    final dir = await _supportDirectory();
    final f = File('${dir.path}/identity.txt');
    if (await f.exists()) {
      return TsIdentity.fromString(data: await f.readAsString());
    }
    final id = await TsIdentity.create();
    await f.writeAsString(id.exportString());
    return id;
  }
}
