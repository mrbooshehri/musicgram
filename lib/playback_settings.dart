import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum PlaybackDefault { remember, on, off }

class PlaybackSettings {
  PlaybackSettings({
    this.resumeOnLaunch = false,
    this.repeat = PlaybackDefault.remember,
    this.shuffle = PlaybackDefault.remember,
    this.artworkSwipe = true,
    this.previousRestartSeconds = 3,
  });

  static const _storage = FlutterSecureStorage();
  static const _key = 'playback_settings';
  bool resumeOnLaunch;
  PlaybackDefault repeat;
  PlaybackDefault shuffle;
  bool artworkSwipe;
  int previousRestartSeconds;

  static PlaybackDefault _parseDefault(Object? value) =>
      PlaybackDefault.values.where((item) => item.name == value).firstOrNull ??
      PlaybackDefault.remember;

  static PlaybackSettings fromJson(Map<String, dynamic> data) =>
      PlaybackSettings(
        resumeOnLaunch: data['resumeOnLaunch'] == true,
        repeat: _parseDefault(data['repeat']),
        shuffle: _parseDefault(data['shuffle']),
        artworkSwipe: data['artworkSwipe'] is bool
            ? data['artworkSwipe'] as bool
            : true,
        previousRestartSeconds:
            data['previousRestartSeconds'] is int &&
                const [0, 3, 5, 10].contains(data['previousRestartSeconds'])
            ? data['previousRestartSeconds'] as int
            : 3,
      );

  Map<String, dynamic> toJson() => {
    'resumeOnLaunch': resumeOnLaunch,
    'repeat': repeat.name,
    'shuffle': shuffle.name,
    'artworkSwipe': artworkSwipe,
    'previousRestartSeconds': previousRestartSeconds,
  };

  static Future<PlaybackSettings> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return PlaybackSettings();
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic>
        ? PlaybackSettings.fromJson(decoded)
        : PlaybackSettings();
  }

  Future<void> save() => _storage.write(key: _key, value: jsonEncode(toJson()));

  static bool resolve(PlaybackDefault setting, bool previous) =>
      switch (setting) {
        PlaybackDefault.remember => previous,
        PlaybackDefault.on => true,
        PlaybackDefault.off => false,
      };
}
