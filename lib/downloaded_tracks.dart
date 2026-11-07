import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'telegram_client.dart';

class DownloadedTracks extends ChangeNotifier {
  static final shared = DownloadedTracks();
  static const _storage = FlutterSecureStorage();
  static const _channel = MethodChannel('musicgram/library');
  final Map<String, String> _uris = {};
  List<String> get savedUris => List.unmodifiable(_uris.values);
  bool contains(String? key) => key != null && _uris.containsKey(key);
  String? uriFor(String? key) => key == null ? null : _uris[key];

  static String? keyFor(Map<String, dynamic> message, {String? sessionId}) {
    final content = message['content'];
    if (content is! Map) return null;
    final media = content['audio'] ?? content['document'];
    if (media is! Map) return null;
    final file = media['audio'] ?? media['document'];
    final remote = file is Map ? file['remote'] : null;
    final unique = remote is Map ? remote['unique_id'] : null;
    final session = sessionId ?? TelegramClient.shared.verifiedSessionId;
    if (session == null &&
        TelegramClient.shared.authorizationState == 'authorizationStateReady') {
      return null;
    }
    String scoped(String key) =>
        session == null || session == 'legacy' ? key : 'session:$session:$key';
    if (unique is String && unique.isNotEmpty) return scoped('file:$unique');
    final chat = message['chat_id'];
    final id = message['id'];
    return chat is int && id is int ? scoped('message:$chat:$id') : null;
  }

  Future<void> load() async {
    final raw = await _storage.read(key: 'telegram_downloaded_tracks');
    if (raw == null) return;
    final values = jsonDecode(raw);
    if (values is! Map) return;
    for (final entry in values.entries) {
      if (entry.key is! String || entry.value is! String) continue;
      try {
        if (await _channel.invokeMethod<bool>('downloadExists', {
              'uri': entry.value,
            }) ==
            true) {
          _uris[entry.key as String] = entry.value as String;
        }
      } on PlatformException {
        /* Keep unknown state when storage cannot be queried. */
      }
    }
    notifyListeners();
  }

  Future<void> mark(String? key, String uri) async {
    if (key == null) return;
    _uris[key] = uri;
    notifyListeners();
    await _storage.write(
      key: 'telegram_downloaded_tracks',
      value: jsonEncode(_uris),
    );
  }
}
