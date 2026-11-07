import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'telegram_client.dart';
import 'telegram_library_cache.dart';
import 'telegram_music_library.dart';
import 'telegram_sync_checkpoint.dart';
import 'telegram_session_store.dart';

/// A single in-process sync shared by settings screens.
class TelegramSyncJob extends ChangeNotifier {
  TelegramSyncJob({
    this.cache,
    TelegramSyncCheckpoint? checkpoint,
    this.sessionId,
    this.notification,
  }) : _checkpoint = checkpoint ?? TelegramSyncCheckpoint();
  static final shared = TelegramSyncJob();
  final TelegramLibraryCache? cache;
  StreamIterator<MusicGroups>? _iterator;
  Future<void>? _operation;
  Future<void>? _recovery;
  final TelegramSyncCheckpoint _checkpoint;
  final String? Function()? sessionId;
  final Future<void> Function(String? message)? notification;
  String? _session;
  Set<int>? recoverableChats;
  void clearRecoveryView() {
    if (recoverableChats == null) return;
    recoverableChats = null;
    notifyListeners();
  }

  bool running = false;
  int tracks = 0;
  int playlists = 0;
  String? error;
  int _generation = 0;

  Future<void> _notifyAndroid(String? message) async {
    if (notification != null) {
      await notification!(message);
      return;
    }
    if (!Platform.isAndroid) return;
    try {
      await const MethodChannel('musicgram/library')
          .invokeMethod<void>('telegramSyncNotification', {'message': message});
    } on PlatformException catch (_) {
      // Notification permission is independent of synchronization.
    } on MissingPluginException catch (_) {}
  }

  void start({Set<int>? chatIds, bool restoring = false}) {
    if (running || _operation != null) return;
    if (Platform.isAndroid) {
      const MethodChannel(
        'musicgram/telegram_sync_control',
      ).setMethodCallHandler((call) async {
        if (call.method == 'cancel') await cancel();
        if (call.method == 'interrupt') await cancel(preserveCheckpoint: true);
      });
    }
    final request = TelegramClient.shared.request;
    final effectiveCache =
        cache ??
        TelegramLibraryCache(
          request: request,
          library: TelegramMusicLibrary(request: request),
        );
    final generation = ++_generation;
    running = true;
    error = null;
    tracks = 0;
    playlists = 0;
    notifyListeners();
    _session =
        sessionId?.call() ??
        (cache == null ? TelegramClient.shared.verifiedSessionId : null);
    final operation = _run(effectiveCache, chatIds, generation, restoring);
    _operation = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_operation, operation)) _operation = null;
      }),
    );
  }

  Future<void> _run(
    TelegramLibraryCache effectiveCache,
    Set<int>? chatIds,
    int generation,
    bool restoring,
  ) async {
    final selected = chatIds?.toSet();
    final pending = selected?.toSet();
    final session = _session;
    try {
      if (cache == null && session == null) {
        throw StateError('Verify your Telegram account first.');
      }
      if (session != null && pending != null) {
        if (restoring) {
          if (await _checkpoint.isCancelled(session)) return;
        } else {
          await _checkpoint.clearCancellation(session);
        }
        await _checkpoint.save(session, pending);
      }
      if (generation != _generation) return;
      await _notifyAndroid('Starting sync…');
      if (generation != _generation) return;
      final groupsToScan = pending == null
          ? <Set<int>?>[null]
          : [
              for (final id in pending) <int>{id},
            ];
      for (final group in groupsToScan) {
        if (generation != _generation) return;
        final iterator = StreamIterator(
          effectiveCache.load(refresh: true, chatIds: group),
        );
        _iterator = iterator;
        try {
          while (await iterator.moveNext()) {
            if (generation != _generation) return;
            final groups = iterator.current;
            final counted = selected == null
                ? groups.entries
                : groups.entries.where((entry) => selected.contains(entry.key));
            playlists = 0;
            tracks = 0;
            for (final entry in counted) {
              playlists++;
              tracks += entry.value.length;
            }
            notifyListeners();
            unawaited(_notifyAndroid('$tracks tracks in $playlists playlists'));
          }
        } finally {
          await iterator.cancel();
          if (identical(_iterator, iterator)) _iterator = null;
        }
        if (generation != _generation) return;
        if (pending != null && group != null) {
          pending.removeAll(group);
          if (session != null) await _checkpoint.save(session, pending);
        }
      }
      if (session != null && pending != null) await _checkpoint.clear(session);
      recoverableChats = null;
    } catch (failure) {
      if (generation == _generation) {
        error = 'Could not sync Telegram music: $failure';
        recoverableChats = pending;
      }
    } finally {
      if (generation == _generation) {
        running = false;
        notifyListeners();
        unawaited(_notifyAndroid(null));
      }
    }
  }

  Future<void> findInterrupted() async {
    final session =
        sessionId?.call() ?? TelegramClient.shared.verifiedSessionId;
    if (session == null || running || _operation != null) return;
    if (await _checkpoint.isCancelled(session)) {
      if ((sessionId?.call() ?? TelegramClient.shared.verifiedSessionId) ==
          session) {
        recoverableChats = null;
        notifyListeners();
      }
      return;
    }
    final pending = await _checkpoint.load(session);
    if ((sessionId?.call() ?? TelegramClient.shared.verifiedSessionId) !=
        session) {
      return;
    }
    recoverableChats = pending == null || pending.isEmpty ? null : pending;
    notifyListeners();
  }

  /// Checks only the active slot; starting TDLib still requires verification.
  Future<bool> hasPendingActiveSession({TelegramSessionStore? sessions}) async {
    final store = sessions ?? TelegramSessionStore();
    final session = await store.activeId();
    if (await _checkpoint.isCancelled(session)) return false;
    final pending = await _checkpoint.load(session);
    return await store.activeId() == session &&
        pending != null &&
        pending.isNotEmpty;
  }

  /// Resumes once the currently active TDLib account has been verified.
  Future<void> resumeInterrupted() {
    final existing = _recovery;
    if (existing != null) return existing;
    late final Future<void> operation;
    operation =
        (() async {
          if (running || _operation != null) return;
          final session =
              sessionId?.call() ?? TelegramClient.shared.verifiedSessionId;
          if (session == null) return;
          if (await _checkpoint.isCancelled(session)) return;
          final pending = await _checkpoint.load(session);
          if ((sessionId?.call() ?? TelegramClient.shared.verifiedSessionId) !=
                  session ||
              running ||
              _operation != null ||
              pending == null ||
              pending.isEmpty) {
            return;
          }
          start(chatIds: pending, restoring: true);
        })().whenComplete(() {
          if (identical(_recovery, operation)) _recovery = null;
        });
    _recovery = operation;
    return operation;
  }

  Future<void> cancel({bool preserveCheckpoint = false}) async {
    if (!running) return;
    ++_generation;
    running = false;
    notifyListeners();
    await _iterator?.cancel();
    await _operation;
    final session = _session;
    if (session != null) {
      if (preserveCheckpoint) {
        recoverableChats = await _checkpoint.load(session);
      } else {
        await _checkpoint.clear(session);
        await _checkpoint.clearCancellation(session);
        recoverableChats = null;
      }
    } else {
      recoverableChats = null;
    }
    notifyListeners();
    await _notifyAndroid(null);
  }
}
