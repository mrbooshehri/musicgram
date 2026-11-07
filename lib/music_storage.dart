import 'dart:io';

import 'package:flutter/services.dart';

import 'downloaded_tracks.dart';

class FolderUsage {
  const FolderUsage(this.folder, this.bytes, this.count);
  final String folder;
  final int bytes;
  final int count;
}

class MusicStorageSummary {
  MusicStorageSummary(this.capacity, this.free, this.local, this.telegram);
  final int capacity;
  final int free;
  final List<FolderUsage> local;
  final List<FolderUsage> telegram;
  int get usedBytes => (capacity - free).clamp(0, capacity);
  int get localBytes => local.fold(0, (sum, entry) => sum + entry.bytes);
  int get telegramBytes => telegram.fold(0, (sum, entry) => sum + entry.bytes);

  factory MusicStorageSummary.fromMap(Map data) {
    final local = <String, (int, int)>{};
    final telegram = <String, (int, int)>{};
    for (final item in (data['files'] as List? ?? [])) {
      if (item is! Map || item['folder'] is! String || item['bytes'] is! int) {
        continue;
      }
      final map = item['telegram'] == true ? telegram : local;
      final name = item['folder'] as String;
      final old = map[name] ?? (0, 0);
      map[name] = (old.$1 + (item['bytes'] as int), old.$2 + 1);
    }
    List<FolderUsage> entries(Map<String, (int, int)> groups) =>
        groups.entries
            .map((e) => FolderUsage(e.key, e.value.$1, e.value.$2))
            .toList()
          ..sort((a, b) => b.bytes.compareTo(a.bytes));
    return MusicStorageSummary(
      (data['capacity'] as int?) ?? 0,
      (data['free'] as int?) ?? 0,
      entries(local),
      entries(telegram),
    );
  }

  static Future<MusicStorageSummary> load() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Storage analysis is available on Android.');
    }
    final data = await const MethodChannel('musicgram/library')
        .invokeMapMethod<String, dynamic>('musicStorageUsage', {
          'downloadUris': DownloadedTracks.shared.savedUris,
        });
    if (data == null) throw StateError('Storage analysis unavailable');
    return MusicStorageSummary.fromMap(data);
  }
}

String formatStorageSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}
