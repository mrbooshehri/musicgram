import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class MusicLibrarySettings {
  MusicLibrarySettings({
    this.minimumSeconds = 0,
    this.excludedFolders = const [],
    this.excludeWhatsApp = true,
    this.excludeTelegram = false,
    this.excludeMessenger = false,
    this.includeUnknownDuration = true,
  });
  static const _storage = FlutterSecureStorage();
  static const _key = 'music_library_settings';
  final int minimumSeconds;
  final List<String> excludedFolders;
  final bool excludeWhatsApp;
  final bool excludeTelegram;
  final bool excludeMessenger;
  final bool includeUnknownDuration;

  static MusicLibrarySettings fromJson(Map<String, dynamic> data) =>
      MusicLibrarySettings(
        minimumSeconds:
            (data['minimumSeconds'] is int ? data['minimumSeconds'] as int : 0)
                .clamp(0, 3600),
        excludedFolders:
            (data['excludedFolders'] is List
                    ? data['excludedFolders'] as List
                    : [])
                .whereType<String>()
                .toList(),
        excludeWhatsApp: data['excludeWhatsApp'] is bool
            ? data['excludeWhatsApp'] as bool
            : true,
        excludeTelegram: data['excludeTelegram'] == true,
        excludeMessenger: data['excludeMessenger'] == true,
        includeUnknownDuration: data['includeUnknownDuration'] is bool
            ? data['includeUnknownDuration'] as bool
            : true,
      );

  Map<String, dynamic> toJson() => {
    'minimumSeconds': minimumSeconds,
    'excludedFolders': excludedFolders,
    'excludeWhatsApp': excludeWhatsApp,
    'excludeTelegram': excludeTelegram,
    'excludeMessenger': excludeMessenger,
    'includeUnknownDuration': includeUnknownDuration,
  };
  static Future<MusicLibrarySettings> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return MusicLibrarySettings();
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic>
        ? MusicLibrarySettings.fromJson(decoded)
        : MusicLibrarySettings();
  }

  Future<void> save() => _storage.write(key: _key, value: jsonEncode(toJson()));

  static final _whatsAppAudioFolder = RegExp(
    r'(?:^|/)whatsapp (?:business )?(?:audio|voice notes)(?:/|$)',
    caseSensitive: false,
  );

  static bool isWhatsAppAudioPath(String path) =>
      _whatsAppAudioFolder.hasMatch(path);

  static final _telegramAudioFolder = RegExp(
    r'(?:^|/)telegram (?:audio|voice)(?:/|$)',
    caseSensitive: false,
  );
  static final _messengerFolder = RegExp(
    r'(?:^|/)(?:com\.facebook\.orca|messenger)(?:/|$)',
    caseSensitive: false,
  );

  bool matches(Map<String, dynamic> song) {
    final path = song['path'] as String? ?? '';
    bool inFolder(String folder) {
      final prefix = folder.endsWith('/') ? folder : '$folder/';
      return path.startsWith(prefix);
    }

    if (excludeWhatsApp && isWhatsAppAudioPath(path)) return false;
    if (excludeTelegram && _telegramAudioFolder.hasMatch(path)) return false;
    if (excludeMessenger && _messengerFolder.hasMatch(path)) return false;
    if (excludedFolders.any(inFolder)) return false;
    final duration = int.tryParse('${song['duration'] ?? ''}');
    if (duration == null || duration <= 0) return includeUnknownDuration;
    return duration >= minimumSeconds * 1000;
  }
}

Future<List<Map<String, dynamic>>> scanMusicLibrary({
  bool filtered = true,
  bool requestPermission = true,
}) async {
  final rows = await const MethodChannel(
    'musicgram/library',
  ).invokeListMethod<dynamic>(requestPermission ? 'songs' : 'songsIfPermitted');
  final songs = (rows ?? [])
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();
  if (!filtered) return songs;
  final settings = await MusicLibrarySettings.load();
  return songs.where(settings.matches).toList();
}
