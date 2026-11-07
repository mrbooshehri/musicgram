import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/telegram_library_cache.dart';
import 'package:musicgram/telegram_music_library.dart';
import 'package:musicgram/telegram_sync_job.dart';
import 'package:musicgram/telegram_sync_checkpoint.dart';
import 'package:musicgram/telegram_session_store.dart';

void main() {
  test('selected sync progress excludes all other cached chats', () async {
    final root = await Directory.systemTemp.createTemp('sync_selected_counts');
    addTearDown(() => root.delete(recursive: true));
    Map<String, Object> song(int chat) => {
      'id': chat,
      'chat_id': chat,
      'content': {'@type': 'messageAudio'},
    };
    await File('${root.path}/telegram_music_9.json').writeAsString(
      jsonEncode({
        'complete': true,
        'groups': {
          for (var id = 1; id <= 83; id++) '$id': [song(id)],
        },
      }),
    );
    final visited = <int>[];
    Future<Map<String, dynamic>> request(Map<String, Object?> query) async {
      if (query['@type'] == 'getMe') return {'id': 9};
      final id = query['chat_id'] as int;
      visited.add(id);
      final filter = query['filter'] as Map;
      return {
        'messages': filter['@type'] == 'searchMessagesFilterAudio'
            ? [song(id)]
            : [],
        'next_from_message_id': 0,
      };
    }

    final cache = TelegramLibraryCache(
      request: request,
      library: TelegramMusicLibrary(request: request),
      directory: () async => root,
    );
    final notifications = <String>[];
    final job = TelegramSyncJob(
      cache: cache,
      notification: (message) async {
        if (message != null) notifications.add(message);
      },
    );
    addTearDown(job.dispose);
    final progress = <(int, int)>[];
    final finished = Completer<void>();
    job.addListener(() {
      progress.add((job.tracks, job.playlists));
      if (!job.running && !finished.isCompleted) finished.complete();
    });
    job.start(chatIds: {1, 2, 3, 4});
    await finished.future;
    expect(job.error, isNull);
    expect(visited.toSet(), {1, 2, 3, 4});
    expect(progress.every((entry) => entry.$1 <= 4 && entry.$2 <= 4), isTrue);
    expect((job.tracks, job.playlists), (4, 4));
    expect(notifications, contains('4 tracks in 4 playlists'));
    expect((await cache.load(cacheOnly: true).last).length, 83);
  });
  test('a native cancellation marker prevents recovery', () async {
    final root = await Directory.systemTemp.createTemp('sync_cancel_marker');
    addTearDown(() => root.delete(recursive: true));
    final checkpoint = TelegramSyncCheckpoint(directory: () async => root);
    await checkpoint.save('legacy', {1});
    await File('${root.path}/telegram_sync_legacy.json.cancelled')
        .writeAsString('cancelled');
    final job = TelegramSyncJob(
      checkpoint: checkpoint,
      sessionId: () => 'legacy',
    );
    addTearDown(job.dispose);
    expect(
      await job.hasPendingActiveSession(
        sessions: TelegramSessionStore(directory: () async => root),
      ),
      isFalse,
    );
    await job.findInterrupted();
    expect(job.recoverableChats, isNull);
    await job.resumeInterrupted();
    expect(job.running, isFalse);
  });
  test('saves the checkpoint before starting foreground sync', () async {
    final root = await Directory.systemTemp.createTemp('sync_checkpoint_first');
    addTearDown(() => root.delete(recursive: true));
    final checkpoint = TelegramSyncCheckpoint(directory: () async => root);
    final observed = Completer<Set<int>?>();
    Future<Map<String, dynamic>> request(Map<String, Object?> query) async {
      if (query['@type'] == 'getMe') return {'id': 8};
      return {'messages': <Object>[], 'next_from_message_id': 0};
    }

    final job = TelegramSyncJob(
      cache: TelegramLibraryCache(
        request: request,
        library: TelegramMusicLibrary(request: request),
        directory: () async => root,
      ),
      checkpoint: checkpoint,
      sessionId: () => 'legacy',
      notification: (message) async {
        if (message == 'Starting sync…') {
          observed.complete(await checkpoint.load('legacy'));
        }
      },
    );
    addTearDown(job.dispose);
    final done = Completer<void>();
    job.addListener(() {
      if (!job.running && !done.isCompleted) done.complete();
    });
    job.start(chatIds: {1, 2});
    expect(await observed.future, {1, 2});
    await done.future;
  });
  test('resumes only unfinished chats for the verified session', () async {
    final root = await Directory.systemTemp.createTemp('automatic_sync_resume');
    addTearDown(() => root.delete(recursive: true));
    final checkpoint = TelegramSyncCheckpoint(directory: () async => root);
    await checkpoint.save('legacy', {2});
    await checkpoint.save('session_other', {3});
    final visited = <int>[];
    Future<Map<String, dynamic>> request(Map<String, Object?> query) async {
      if (query['@type'] == 'getMe') return {'id': 8};
      visited.add(query['chat_id'] as int);
      return {'messages': <Object>[], 'next_from_message_id': 0};
    }

    final cache = TelegramLibraryCache(
      request: request,
      library: TelegramMusicLibrary(request: request),
      directory: () async => root,
    );
    String? session;
    final job = TelegramSyncJob(
      cache: cache,
      checkpoint: checkpoint,
      sessionId: () => session,
    );
    addTearDown(job.dispose);
    final sessions = TelegramSessionStore(directory: () async => root);
    expect(await job.hasPendingActiveSession(sessions: sessions), isTrue);
    await job.resumeInterrupted();
    expect(job.running, isFalse);
    session = 'legacy';
    final done = Completer<void>();
    job.addListener(() {
      if (!job.running && !done.isCompleted) done.complete();
    });
    await Future.wait([job.resumeInterrupted(), job.resumeInterrupted()]);
    await done.future;
    expect(visited, [2, 2]);
    expect(await checkpoint.load('legacy'), isNull);
    expect(await checkpoint.load('session_other'), {3});
    expect(await job.hasPendingActiveSession(sessions: sessions), isFalse);
  });
  test('interrupted sync keeps only unfinished chats in checkpoint', () async {
    final root = await Directory.systemTemp.createTemp('sync_resume');
    addTearDown(() => root.delete(recursive: true));
    Future<Map<String, dynamic>> request(Map<String, Object?> query) async {
      if (query['@type'] == 'getMe') return {'id': 8};
      if (query['chat_id'] == 2) throw StateError('offline');
      return {'messages': <Object>[], 'next_from_message_id': 0};
    }

    final checkpoint = TelegramSyncCheckpoint(directory: () async => root);
    final cache = TelegramLibraryCache(
      request: request,
      library: TelegramMusicLibrary(request: request),
      directory: () async => root,
    );
    final job = TelegramSyncJob(
      cache: cache,
      checkpoint: checkpoint,
      sessionId: () => 'legacy',
    );
    final done = Completer<void>();
    job.addListener(() {
      if (!job.running && !done.isCompleted) done.complete();
    });
    job.start(chatIds: {1, 2});
    await done.future;
    expect(job.error, contains('offline'));
    expect(await checkpoint.load('legacy'), {2});
    job.dispose();
  });
  test(
    'checkpoints are isolated by verified session and can be cleared',
    () async {
      final root = await Directory.systemTemp.createTemp('sync_checkpoints');
      addTearDown(() => root.delete(recursive: true));
      final store = TelegramSyncCheckpoint(directory: () async => root);
      await store.save('legacy', {1, -2});
      await store.save('session_other', {3});
      expect(await store.load('legacy'), {1, -2});
      expect(await store.load('session_other'), {3});
      await store.clear('legacy');
      expect(await store.load('legacy'), isNull);
      expect(await store.load('session_other'), {3});
      await expectLater(store.load('../unsafe'), throwsArgumentError);
    },
  );
  test(
    'sync runs independently of settings and reports discovered tracks',
    () async {
      final root = await Directory.systemTemp.createTemp('sync_job');
      addTearDown(() => root.delete(recursive: true));
      Future<Map<String, dynamic>> request(Map<String, Object?> request) async {
        if (request['@type'] == 'getMe') return {'id': 9};
        final filter = request['filter'] as Map;
        return {
          'messages': filter['@type'] == 'searchMessagesFilterAudio'
              ? [
                  {
                    'id': 4,
                    'chat_id': 7,
                    'content': {'@type': 'messageAudio'},
                  },
                ]
              : [],
          'next_offset': '',
        };
      }

      final cache = TelegramLibraryCache(
        request: request,
        library: TelegramMusicLibrary(request: request),
        directory: () async => root,
      );
      final job = TelegramSyncJob(cache: cache);
      final finished = Completer<void>();
      job.addListener(() {
        if (!job.running && !finished.isCompleted) finished.complete();
      });
      job.start();
      expect(job.running, isTrue);
      await finished.future;
      expect(job.error, isNull);
      expect(job.tracks, 1);
      expect(job.playlists, 1);
      expect((await cache.load(cacheOnly: true).last)[7], hasLength(1));
      job.dispose();
    },
  );
}
