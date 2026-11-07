import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/telegram_library_cache.dart';
import 'package:musicgram/telegram_music_library.dart';
import 'package:musicgram/telegram_sync_selection.dart';

void main() {
  test('chat selections remain separate for each Telegram account', () async {
    final dir = await Directory.systemTemp.createTemp(
      'telegram_selection_accounts',
    );
    addTearDown(() => dir.delete(recursive: true));
    var account = 7;
    Future<Map<String, dynamic>> request(Map<String, Object?> req) async => {
      'id': account,
    };
    final selection = TelegramSyncSelection(
      request: request,
      directory: () async => dir,
    );
    await selection.save({1, 2});
    account = 8;
    expect(await selection.load(), isEmpty);
    await selection.save({3});
    account = 7;
    expect(await selection.load(), {1, 2});
  });
  test(
    'selected playlist view excludes unselected cached chats without scanning',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'selected_playlist_view',
      );
      addTearDown(() => dir.delete(recursive: true));
      var scans = 0;
      Future<Map<String, dynamic>> request(Map<String, Object?> req) async {
        if (req['@type'] == 'getMe') return {'id': 77};
        scans++;
        return {'messages': [], 'next_offset': ''};
      }

      await File('${dir.path}/telegram_music_77.json').writeAsString(
        '{"complete":true,"groups":{"1":[{"id":1}],"2":[{"id":2}]}}',
      );
      await TelegramSyncSelection(
        request: request,
        directory: () async => dir,
      ).save({1});
      final cache = TelegramLibraryCache(
        request: request,
        library: TelegramMusicLibrary(request: request),
        directory: () async => dir,
      );
      final groups = await cache.loadSelected().last;
      expect(groups.keys, [1]);
      expect(scans, 0);
      expect(
        await File('${dir.path}/telegram_music_77.json').readAsString(),
        contains('"2"'),
      );
    },
  );
  test('selected sync searches only selected chats and preserves other cached chats', () async {
    final dir = await Directory.systemTemp.createTemp('music_cache_selected');
    addTearDown(() => dir.delete(recursive: true));
    var selective = false;
    final searched = <int>[];
    Future<Map<String, dynamic>> request(Map<String, Object?> req) async {
      if (req['@type'] == 'getMe') return {'id': 77};
      final filter = req['filter'] as Map;
      final audio = filter['@type'] == 'searchMessagesFilterAudio';
      if (!selective) {
        return {
          'messages': audio
              ? [
                  {
                    'id': 1,
                    'chat_id': 1,
                    'content': {'@type': 'messageAudio'},
                  },
                  {
                    'id': 2,
                    'chat_id': 2,
                    'content': {'@type': 'messageAudio'},
                  },
                ]
              : [],
          'next_offset': '',
        };
      }
      expect(req['@type'], 'searchChatMessages');
      searched.add(req['chat_id'] as int);
      return {
        'messages': audio
            ? [
                {
                  'id': 3,
                  'chat_id': 1,
                  'content': {'@type': 'messageAudio'},
                },
              ]
            : [],
        'next_from_message_id': 0,
      };
    }

    final cache = TelegramLibraryCache(
      request: request,
      library: TelegramMusicLibrary(request: request),
      directory: () async => dir,
    );
    await cache.load().drain<void>();
    selective = true;
    final result = await cache.load(refresh: true, chatIds: {1}).last;
    expect(searched, [1, 1]);
    expect(result[1]!.single['id'], 3);
    expect(result[2]!.single['id'], 2);
    expect((await cache.load(cacheOnly: true).last)[2]!.single['id'], 2);
  });
  test('cache-only access never starts a Telegram search', () async {
    final dir = await Directory.systemTemp.createTemp('music_cache_only');
    addTearDown(() => dir.delete(recursive: true));
    var searches = 0;
    Future<Map<String, dynamic>> request(Map<String, Object?> req) async {
      if (req['@type'] == 'getMe') return {'id': 10};
      searches++;
      return {'messages': [], 'next_offset': ''};
    }

    final cache = TelegramLibraryCache(
      request: request,
      library: TelegramMusicLibrary(request: request),
      directory: () async => dir,
    );
    expect(await cache.load(cacheOnly: true).last, isEmpty);
    expect(searches, 0);
  });
  test(
    'saves a first page even when the screen closes before sync completes',
    () async {
      final dir = await Directory.systemTemp.createTemp('music_cache_partial');
      addTearDown(() => dir.delete(recursive: true));
      Future<Map<String, dynamic>> request(Map<String, Object?> req) async {
        if (req['@type'] == 'getMe') return {'id': 9};
        return {
          'messages': [
            {
              'id': 3,
              'chat_id': 2,
              'content': {'@type': 'messageAudio'},
            },
          ],
          'next_offset': 'next',
        };
      }

      final cache = TelegramLibraryCache(
        request: request,
        library: TelegramMusicLibrary(request: request),
        directory: () async => dir,
      );
      final first = StreamIterator(cache.load());
      expect(await first.moveNext(), isTrue);
      await first.cancel();
      final reopened = StreamIterator(cache.load());
      expect(await reopened.moveNext(), isTrue);
      expect(reopened.current[2], hasLength(1));
      await reopened.cancel();
    },
  );
  test(
    'reopening a completed cache does not scan again, even when empty',
    () async {
      final dir = await Directory.systemTemp.createTemp('music_cache_empty');
      addTearDown(() => dir.delete(recursive: true));
      var searches = 0;
      Future<Map<String, dynamic>> request(Map<String, Object?> req) async {
        if (req['@type'] == 'getMe') return {'id': 7};
        searches++;
        return {'messages': [], 'next_offset': ''};
      }

      final cache = TelegramLibraryCache(
        request: request,
        library: TelegramMusicLibrary(request: request),
        directory: () async => dir,
      );
      await cache.load().drain<void>();
      expect(searches, 2);
      expect(await cache.load().last, isEmpty);
      expect(searches, 2);
      await cache.load(refresh: true).drain<void>();
      expect(searches, 4);
    },
  );
  test(
    'restores cached tracks before sync and retains them after a failure',
    () async {
      final dir = await Directory.systemTemp.createTemp('music_cache_test');
      addTearDown(() => dir.delete(recursive: true));
      var fail = false;
      Future<Map<String, dynamic>> request(Map<String, Object?> req) async {
        if (req['@type'] == 'getMe') return {'id': 42};
        if (fail) throw StateError('offline');
        final filter = req['filter'] as Map;
        return {
          'messages': filter['@type'] == 'searchMessagesFilterAudio'
              ? [
                  {
                    'id': 2,
                    'chat_id': 1,
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
        directory: () async => dir,
      );
      await cache.load().drain<void>();
      fail = true;
      final stream = StreamIterator(cache.load(refresh: true));
      expect(await stream.moveNext(), isTrue);
      expect(stream.current[1], hasLength(1));
      await expectLater(stream.moveNext(), throwsStateError);
      await stream.cancel();
      expect(await File('${dir.path}/telegram_music_42.json').exists(), isTrue);
    },
  );
}
