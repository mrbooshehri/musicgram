import 'dart:io';

import 'package:flutter/services.dart';

/// Shares embedded artwork between the main and mini players.
class EmbeddedArtwork {
  static final Map<String, Future<Uint8List?>> _cache = {};
  static final Map<String, DateTime> _retryAfter = {};

  static Future<Uint8List?> load(String path) {
    final retryAt = _retryAfter[path];
    if (retryAt != null && DateTime.now().isBefore(retryAt)) {
      return Future.value(null);
    }
    _retryAfter.remove(path);
    final previous = _cache.remove(path);
    if (previous != null) {
      _cache[path] = previous;
      return previous;
    }
    late final Future<Uint8List?> future;
    future =
        (() async {
          if (!Platform.isAndroid) return null;
          try {
            return await const MethodChannel('musicgram/library')
                .invokeMethod<Uint8List>('artwork', {'path': path});
          } catch (_) {
            return null;
          }
        })().then((bytes) {
          if ((bytes == null || bytes.isEmpty) &&
              identical(_cache[path], future)) {
            _cache.remove(path);
            _retryAfter[path] = DateTime.now().add(const Duration(seconds: 10));
            if (_retryAfter.length > 30) {
              _retryAfter.remove(_retryAfter.keys.first);
            }
          }
          return bytes;
        });
    _cache[path] = future;
    if (_cache.length > 30) _cache.remove(_cache.keys.first);
    return future;
  }
}
