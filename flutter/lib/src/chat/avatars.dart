import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../myts/controller.dart';
import 'chat_controller.dart';

/// Loads contact avatars one at a time (three in flight), remembering both hits
/// and misses for the unlocked session. Bytes are never written to disk and the
/// signed download URL is never kept.
class AvatarLoader {
  final Future<Uint8List?> Function(String matrixId) _fetch;
  final _cache = <String, Uint8List?>{};
  final _inFlight = <String, Future<Uint8List?>>{};
  final _queue = Queue<void Function()>();
  int _running = 0;

  AvatarLoader(this._fetch);

  Future<Uint8List?> load(String matrixId) {
    if (_cache.containsKey(matrixId)) return Future.value(_cache[matrixId]);
    return _inFlight.putIfAbsent(matrixId, () {
      final done = Completer<Uint8List?>();
      _queue.add(() async {
        _running++;
        try {
          final bytes = await _fetch(matrixId);
          _cache[matrixId] = bytes;
          done.complete(bytes);
        } catch (_) {
          // A transient failure is retried on the next unlock, not in a loop.
          _cache[matrixId] = null;
          done.complete(null);
        } finally {
          _running--;
          _inFlight.remove(matrixId);
          _pump();
        }
      });
      _pump();
      return done.future;
    });
  }

  void _pump() {
    while (_running < 3 && _queue.isNotEmpty) {
      _queue.removeFirst()();
    }
  }
}

final avatarLoaderProvider = Provider<AvatarLoader>((ref) {
  // Rebuilt (and so emptied) whenever the chat locks or the account changes.
  ref.watch(myTsProvider.select((s) => s.email));
  ref.watch(chatProvider.select((s) => s.phase == ChatPhase.locked));
  return AvatarLoader((matrixId) async {
    final host = ref.read(chatProvider).account.host;
    final session = await ref.read(chatProvider.notifier).sessionToken();
    if (host.isEmpty || session == null) return null;
    return ref.read(myTsApiProvider).contactAvatar(session, matrixId, host);
  });
});

final avatarProvider = FutureProvider.family<Uint8List?, String>((ref, id) {
  if (id.isEmpty) return null;
  return ref.watch(avatarLoaderProvider).load(id);
});
