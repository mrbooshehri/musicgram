import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class NotificationSettings {
  static final showArtwork = ValueNotifier<bool>(true);
  static final showCompactSkip = ValueNotifier<bool>(true);
  static const _storage = FlutterSecureStorage();
  static const _key = 'notification_settings';
  static Future<void> _writes = Future.value();

  static Future<void> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return;
    final data = jsonDecode(raw);
    if (data is Map && data['showArtwork'] is bool) {
      showArtwork.value = data['showArtwork'] as bool;
    }
    if (data is Map && data['showCompactSkip'] is bool) {
      showCompactSkip.value = data['showCompactSkip'] as bool;
    }
  }

  static Future<void> save(bool value) => _save(artwork: value);

  static Future<void> saveCompactSkip(bool value) => _save(compactSkip: value);

  static Future<void> _save({bool? artwork, bool? compactSkip}) {
    final write = _writes.then((_) async {
      final nextArtwork = artwork ?? showArtwork.value;
      final nextCompactSkip = compactSkip ?? showCompactSkip.value;
      await _storage.write(
        key: _key,
        value: jsonEncode({
          'showArtwork': nextArtwork,
          'showCompactSkip': nextCompactSkip,
        }),
      );
      showArtwork.value = nextArtwork;
      showCompactSkip.value = nextCompactSkip;
    });
    _writes = write.catchError((_) {});
    return write;
  }
}
