import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'telegram_session_store.dart';
import 'telegram_client.dart';

class PlaylistStore {
  PlaylistStore({this.directory, this.sessionId, this.telegramAccessible});
  final Future<Directory> Function()? directory;
  final Future<String> Function()? sessionId;
  final bool Function()? telegramAccessible;
  String? _loadedSession;
  bool? _loadedAccess;
  static Future<void> _writes = Future.value();

  Future<String> _session() =>
      sessionId?.call() ??
      TelegramSessionStore(directory: directory).activeId();

  Future<File> _file() async => File(
    '${(await (directory?.call() ?? getApplicationSupportDirectory())).path}/playlists.json',
  );

  bool get _canAccessTelegram =>
      telegramAccessible?.call() ??
      (TelegramClient.shared.authorizationState != 'authorizationStateReady' ||
          TelegramClient.shared.isAccountVerified);

  bool _visible(Map<String, dynamic> playlist, String session, bool access) {
    if (playlist['type'] != 'telegram') return true;
    return access && (playlist['sessionId'] ?? 'legacy') == session;
  }

  Future<List<Map<String, dynamic>>> _readAll() async {
    try {
      final data = jsonDecode(await (await _file()).readAsString());
      if (data is! List) throw const FormatException('Invalid playlist data');
      return data
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } on PathNotFoundException {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> load() async {
    final session = await _session();
    final access = _canAccessTelegram;
    final all = await _readAll();
    if (await _session() != session || _canAccessTelegram != access) {
      throw StateError('Telegram account changed while loading playlists.');
    }
    _loadedSession = session;
    _loadedAccess = access;
    return all.where((item) => _visible(item, session, access)).toList();
  }

  Future<void> save(List<Map<String, dynamic>> playlists) {
    final write = _writes.then((_) async {
      final session = await _session();
      final access = _canAccessTelegram;
      if ((_loadedSession != null && _loadedSession != session) ||
          (_loadedAccess != null && _loadedAccess != access)) {
        throw StateError(
          'Telegram account changed. Reload playlists before saving.',
        );
      }
      final existing = await _readAll();
      if (!access && playlists.any((item) => item['type'] == 'telegram')) {
        throw StateError(
          'Verify the Telegram account before changing Telegram playlists.',
        );
      }
      final hidden = existing.where((item) => !_visible(item, session, access));
      final visible = playlists.map((item) {
        final copy = Map<String, dynamic>.of(item);
        if (copy['type'] == 'telegram') {
          if (session == 'legacy') {
            copy.remove('sessionId');
          } else {
            copy['sessionId'] = session;
          }
        }
        return copy;
      });
      final file = await _file();
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode([...visible, ...hidden]),
        flush: true,
      );
      if (await _session() != session || _canAccessTelegram != access) {
        await temporary.delete();
        throw StateError('Telegram account changed while saving playlists.');
      }
      await temporary.rename(file.path);
      _loadedSession = session;
      _loadedAccess = access;
    });
    _writes = write.catchError((_) {});
    return write;
  }
}
