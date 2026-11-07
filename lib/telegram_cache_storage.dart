import 'dart:io';

import 'package:path_provider/path_provider.dart';

class TelegramCacheStorage {
  TelegramCacheStorage({this.directory});
  final Future<Directory> Function()? directory;

  Future<List<File>> _files() async {
    final dir = await (directory?.call() ?? getApplicationSupportDirectory());
    if (!await dir.exists()) return [];
    final files = <File>[];
    await for (final entry in dir.list(followLinks: false)) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last;
      if (RegExp(r'^telegram_music_[0-9]+\.json$').hasMatch(name)) {
        files.add(entry);
      }
    }
    return files;
  }

  Future<int> size() async {
    var bytes = 0;
    for (final file in await _files()) {
      bytes += await file.length();
    }
    return bytes;
  }

  Future<void> clear() async {
    for (final file in await _files()) {
      await file.delete();
    }
  }
}
