import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'telegram_music_library.dart';
import 'telegram_sync_selection.dart';

typedef MusicGroups = Map<int, List<Map<String, dynamic>>>;

class TelegramLibraryCache {
  TelegramLibraryCache({
    required this.request,
    required this.library,
    this.directory,
  });
  final TelegramRequest request;
  final TelegramMusicLibrary library;
  final Future<Directory> Function()? directory;

  /// Loads only the selected chats without starting a discovery scan.
  Stream<MusicGroups> loadSelected() async* {
    final selected = await TelegramSyncSelection(
      request: request,
      directory: directory,
    ).load();
    await for (final groups in load(cacheOnly: true)) {
      yield {
        for (final entry in groups.entries)
          if (selected.contains(entry.key)) entry.key: entry.value,
      };
    }
  }

  Stream<MusicGroups> load({
    bool refresh = false,
    bool cacheOnly = false,
    Set<int>? chatIds,
  }) async* {
    final user = await request({'@type': 'getMe'});
    final id = user['id'];
    if (id is! int) throw const FormatException('Invalid Telegram account');
    final dir = await (directory?.call() ?? getApplicationSupportDirectory());
    final file = File('${dir.path}/telegram_music_$id.json');
    MusicGroups saved = {};
    var complete = false;
    var cacheExists = false;
    DateTime? syncedAt;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        cacheExists = true;
        complete = decoded['complete'] == true;
        final timestamp = decoded['syncedAt'];
        if (timestamp is int) {
          syncedAt = DateTime.fromMillisecondsSinceEpoch(
            timestamp,
            isUtc: true,
          );
        }
        final groups = decoded['groups'] is Map
            ? decoded['groups'] as Map
            : decoded;
        saved = {
          for (final e in groups.entries)
            if (int.tryParse(e.key.toString()) != null && e.value is List)
              int.parse(e.key.toString()): (e.value as List)
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList(),
        };
      }
    } on FileSystemException catch (_) {
      // A missing cache is normal on the first sync.
    } on FormatException catch (_) {
      // A damaged cache is replaced after the next successful sync.
    }
    if (cacheExists) yield saved;
    if (cacheOnly) {
      if (!cacheExists) yield {};
      return;
    }
    if (cacheExists &&
        complete &&
        !refresh &&
        syncedAt != null &&
        DateTime.now().toUtc().difference(syncedAt) <
            const Duration(minutes: 15)) {
      return;
    }
    Future<void> save(MusicGroups groups, {required bool complete}) async {
      try {
        await dir.create(recursive: true);
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(
          jsonEncode({
            'complete': complete,
            if (complete)
              'syncedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
            'groups': {for (final e in groups.entries) '${e.key}': e.value},
          }),
          flush: true,
        );
        await temp.rename(file.path);
      } on FileSystemException catch (_) {
        if (chatIds != null) rethrow;
        // Discovery remains usable when the local cache cannot be written.
      }
    }

    MusicGroups latest = {};
    await for (final batch
        in chatIds == null
            ? library.discover()
            : library.discoverChats(chatIds)) {
      latest = batch;
      final merged = <int, List<Map<String, dynamic>>>{
        for (final e in saved.entries) e.key: List.of(e.value),
      };
      for (final entry in batch.entries) {
        final byId = <Object?, Map<String, dynamic>>{
          for (final item in merged[entry.key] ?? <Map<String, dynamic>>[])
            item['id']: item,
          for (final item in entry.value) item['id']: item,
        };
        merged[entry.key] = byId.values.toList();
      }
      if (!complete && chatIds == null) await save(merged, complete: false);
      yield merged;
    }
    final result = chatIds == null
        ? latest
        : <int, List<Map<String, dynamic>>>{
            for (final entry in saved.entries)
              if (!chatIds.contains(entry.key)) entry.key: entry.value,
            ...latest,
          };
    await save(result, complete: complete || chatIds == null);
    yield result;
  }
}
