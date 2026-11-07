import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'telegram_client.dart';
import 'telegram_session_store.dart';
import 'telegram_sync_checkpoint.dart';
import 'telegram_sync_job.dart';

/// Restores the existing TDLib session after Android restarts the sync service.
class TelegramBackgroundRecovery {
  static Future<void>? _running;
  static bool _cancelled = false;
  static const _control = MethodChannel('musicgram/telegram_sync_control');
  static const _library = MethodChannel('musicgram/library');

  static Future<void>? get running => _running;

  static void start() {
    if (_running != null) return;
    _cancelled = false;
    _control.setMethodCallHandler((call) async {
      if (call.method == 'cancel') {
        _cancelled = true;
        final session = await TelegramSessionStore().activeId();
        await TelegramSyncCheckpoint().clear(session);
        await TelegramSyncJob.shared.cancel();
        await TelegramSyncCheckpoint().clearCancellation(session);
      } else if (call.method == 'interrupt') {
        _cancelled = true;
        await TelegramSyncJob.shared.cancel(preserveCheckpoint: true);
      }
    });
    late final Future<void> operation;
    operation = _restore().whenComplete(() {
      if (identical(_running, operation)) _running = null;
    });
    _running = operation;
  }

  static Future<void> _finishNotification() async {
    try {
      await _library.invokeMethod<void>('telegramSyncNotification', {
        'message': null,
      });
    } on PlatformException catch (_) {
      // The checkpoint remains available for recovery when the app is opened.
    } on MissingPluginException catch (_) {}
  }

  @visibleForTesting
  static Future<void> restoreForTesting({
    required TelegramClient client,
    required TelegramSessionStore sessions,
    required TelegramSyncJob job,
    required int apiId,
    required String apiHash,
  }) => _restore(
    client: client,
    sessions: sessions,
    job: job,
    apiId: apiId,
    apiHash: apiHash,
  );

  static Future<void> _restore({
    TelegramClient? client,
    TelegramSessionStore? sessions,
    TelegramSyncJob? job,
    int apiId = const int.fromEnvironment('TELEGRAM_API_ID'),
    String apiHash = const String.fromEnvironment('TELEGRAM_API_HASH'),
  }) async {
    var started = false;
    try {
      job ??= TelegramSyncJob.shared;
      sessions ??= TelegramSessionStore();
      if (job.running) {
        started = true;
        return;
      }
      if (apiId <= 0 ||
          apiHash.isEmpty ||
          !await job.hasPendingActiveSession(sessions: sessions) ||
          _cancelled) {
        return;
      }
      client ??= TelegramClient.shared;
      final session = await sessions.activeId();
      if (client.isAccountVerified && client.verifiedSessionId == session) {
        await job.resumeInterrupted();
        started = job.running;
        return;
      }
      await client.create();
      var response = client.receive();
      await client.send({'@type': 'getAuthorizationState'});
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      var parametersSent = false;
      while (!_cancelled && DateTime.now().isBefore(deadline)) {
        final update = await response;
        response = client.receive();
        if (update == null) continue;
        if (update['@type'] == 'error') {
          throw StateError('Telegram recovery failed.');
        }
        final state = update['@type'] == 'updateAuthorizationState'
            ? update['authorization_state']
            : update;
        final type = state is Map ? state['@type'] : null;
        if (type == 'authorizationStateWaitTdlibParameters' &&
            !parametersSent) {
          parametersSent = true;
          final directory = await sessions.directoryFor(session);
          await client.send({
            '@type': 'setTdlibParameters',
            'database_directory': directory.path,
            'use_message_database': true,
            'use_secret_chats': false,
            'api_id': apiId,
            'api_hash': apiHash,
            'system_language_code': 'en',
            'device_model': 'Android',
            'application_version': '0.1.0',
          });
        } else if (type == 'authorizationStateReady') {
          await client.verifyAccount(store: sessions);
          if (_cancelled || client.verifiedSessionId != session) return;
          await job.resumeInterrupted();
          started = job.running;
          return;
        } else if (type == 'authorizationStateWaitPhoneNumber' ||
            type == 'authorizationStateWaitCode' ||
            type == 'authorizationStateWaitPassword' ||
            type == 'authorizationStateClosed') {
          return;
        }
      }
    } catch (_) {
      // Keep the checkpoint so the user can retry from Telegram settings.
    } finally {
      if (!started) await _finishNotification();
    }
  }
}
