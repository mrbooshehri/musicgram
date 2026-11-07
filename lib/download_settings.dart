import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DownloadSettings extends ChangeNotifier {
  static final shared = DownloadSettings();
  static const _storage = FlutterSecureStorage();
  String folder = 'MusicGram';
  int concurrency = 1;

  Future<void> load() async {
    final raw = await _storage.read(key: 'telegram_download_settings');
    if (raw == null) return;
    final data = jsonDecode(raw);
    if (data is! Map) return;
    if (data['folder'] is String && validFolder(data['folder'] as String)) {
      folder = data['folder'] as String;
    }
    if (data['concurrency'] is int) {
      concurrency = (data['concurrency'] as int).clamp(1, 3);
    }
    notifyListeners();
  }

  static bool validFolder(String value) =>
      value.trim().isNotEmpty &&
      value != '.' &&
      value != '..' &&
      !RegExp(r'[\\/:*?"<>|\x00-\x1f]').hasMatch(value);

  Future<void> save(String newFolder, int newConcurrency) async {
    final clean = newFolder.trim();
    if (!validFolder(clean) || newConcurrency < 1 || newConcurrency > 3) {
      throw ArgumentError('Invalid download settings');
    }
    await _storage.write(
      key: 'telegram_download_settings',
      value: jsonEncode({'folder': clean, 'concurrency': newConcurrency}),
    );
    folder = clean;
    concurrency = newConcurrency;
    notifyListeners();
  }
}
