import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/telegram_background_recovery.dart';
import 'package:musicgram/telegram_client.dart';
import 'package:musicgram/telegram_library_cache.dart';
import 'package:musicgram/telegram_music_library.dart';
import 'package:musicgram/telegram_session_store.dart';
import 'package:musicgram/telegram_sync_checkpoint.dart';
import 'package:musicgram/telegram_sync_job.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'restores and verifies the saved session before resuming its chats',
    () async {
      final root = await Directory.systemTemp.createTemp('background_recovery');
      addTearDown(() => root.delete(recursive: true));
      final sessions = TelegramSessionStore(directory: () async => root);
      await sessions.verifyOwner(42);
      final checkpoint = TelegramSyncCheckpoint(directory: () async => root);
      await checkpoint.save('legacy', {7});
      const channel = MethodChannel('musicgram/tdlib');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final events = Queue<String>();
      Completer<String?>? pending;
      void deliver(Map<String, dynamic> event) {
        final encoded = jsonEncode({'@client_id': 1, ...event});
        final waiter = pending;
        if (waiter == null) {
          events.add(encoded);
        } else {
          pending = null;
          waiter.complete(encoded);
        }
      }

      String? database;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'create') return 1;
        if (call.method == 'receive') {
          if (events.isNotEmpty) return events.removeFirst();
          pending = Completer<String?>();
          return pending!.future;
        }
        if (call.method == 'send') {
          final request =
              jsonDecode(call.arguments['request'] as String) as Map;
          switch (request['@type']) {
            case 'getAuthorizationState':
              deliver({'@type': 'authorizationStateWaitTdlibParameters'});
            case 'setTdlibParameters':
              database = request['database_directory'] as String;
              deliver({
                '@type': 'updateAuthorizationState',
                'authorization_state': {'@type': 'authorizationStateReady'},
              });
            case 'getMe':
              deliver({'@type': 'user', 'id': 42, '@extra': request['@extra']});
          }
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final client = TelegramClient.forTesting();
      final queried = <int>[];
      Future<Map<String, dynamic>> request(Map<String, Object?> query) async {
        if (query['@type'] == 'getMe') return {'id': 42};
        queried.add(query['chat_id'] as int);
        return {'messages': <Object>[], 'next_from_message_id': 0};
      }

      final cache = TelegramLibraryCache(
        request: request,
        library: TelegramMusicLibrary(request: request),
        directory: () async => root,
      );
      final job = TelegramSyncJob(
        cache: cache,
        checkpoint: checkpoint,
        sessionId: () => client.verifiedSessionId,
      );
      addTearDown(job.dispose);
      final done = Completer<void>();
      job.addListener(() {
        if (!job.running && !done.isCompleted) done.complete();
      });
      await TelegramBackgroundRecovery.restoreForTesting(
        client: client,
        sessions: sessions,
        job: job,
        apiId: 1,
        apiHash: 'test',
      );
      await done.future.timeout(const Duration(seconds: 3));
      expect(database, '${root.path}/telegram');
      expect(client.verifiedSessionId, 'legacy');
      expect(queried, [7, 7]);
      expect(await checkpoint.load('legacy'), isNull);
    },
  );
}
