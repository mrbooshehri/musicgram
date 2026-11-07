import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'telegram_playback_log.dart';
import 'telegram_session_store.dart';
import 'telegram_errors.dart';
import 'telegram_connection_log.dart';

/// Android bridge to the TDLib JSON interface.
class TelegramClient extends ChangeNotifier {
  TelegramClient._();
  @visibleForTesting
  TelegramClient.forTesting();
  static final TelegramClient shared = TelegramClient._();
  static const _channel = MethodChannel('musicgram/tdlib');
  int? _clientId;
  bool _loggingOut = false;
  bool _switchingSession = false;
  final StreamController<Map<String, dynamic>> _updates =
      StreamController.broadcast();
  bool _receiverStarted = false;
  bool get isRunning =>
      _receiverStarted &&
      _clientId != null &&
      authorizationState != 'authorizationStateClosed';
  String? authorizationState;
  String? verifiedSessionId;
  Future<void>? _verification;
  bool get isAccountVerified =>
      authorizationState == 'authorizationStateReady' &&
      verifiedSessionId != null;
  String? activeProxyKey;
  bool connected = false;
  bool get proxyConnected => connected && activeProxyKey != null;
  int _connectionRevision = 0;
  void proxySwitchStarted() {
    connected = false;
    activeProxyKey = null;
    notifyListeners();
  }

  void proxyEnabled(String key) {
    activeProxyKey = key;
    notifyListeners();
  }

  int _requestId = 0;
  final Map<String, Completer<Map<String, dynamic>>> _requests = {};

  @visibleForTesting
  void updateConnectionInfo(Map<String, dynamic> update) {
    if (update['@type'] == 'updateConnectionState') {
      final state = update['state'];
      _connectionRevision++;
      connected =
          state is Map &&
          (state['@type'] == 'connectionStateReady' ||
              state['@type'] == 'connectionStateUpdating');
      final name = state is Map ? state['@type'] : null;
      if (name is String && name.startsWith('connectionState')) {
        recordTelegramConnection('Connection: $name');
      }
      notifyListeners();
    } else if (update['@extra'] == 'proxy_status' &&
        (update['@type'] == 'proxies' || update['@type'] == 'addedProxies')) {
      activeProxyKey = null;
      final proxies = update['proxies'];
      if (proxies is List) {
        for (final item in proxies) {
          if (item is! Map || item['is_enabled'] != true) continue;
          final proxy = item['proxy'] is Map ? item['proxy'] as Map : item;
          final host = proxy['server'];
          final port = proxy['port'];
          if (host is String && port is int) activeProxyKey = '$host:$port';
          break;
        }
      }
      notifyListeners();
    }
  }

  /// Refreshes TDLib's current state if no newer connection update arrived.
  Future<void> refreshConnectionState() async {
    final revision = _connectionRevision;
    final response = await request({'@type': 'getCurrentState'});
    if (revision != _connectionRevision) return;
    final updates = response['updates'];
    if (updates is! List) return;
    for (final item in updates) {
      if (item is Map && item['@type'] == 'updateConnectionState') {
        updateConnectionInfo(Map<String, dynamic>.from(item));
        break;
      }
    }
  }

  @visibleForTesting
  void updateAuthorizationInfo(Map<String, dynamic> update) {
    final type = update['@type'];
    final state = type == 'updateAuthorizationState'
        ? update['authorization_state']
        : update;
    final next = state is Map ? state['@type'] : null;
    if (next is String &&
        next.startsWith('authorizationState') &&
        authorizationState != next) {
      authorizationState = next;
      recordTelegramConnection('Authorization: $next');
      if (next != 'authorizationStateReady') verifiedSessionId = null;
      notifyListeners();
    }
  }

  Future<void> verifyAccount({TelegramSessionStore? store}) {
    if (isAccountVerified) return Future.value();
    if (_verification != null) return _verification!;
    final expectedClient = _clientId;
    late final Future<void> operation;
    operation =
        (() async {
          if (authorizationState != 'authorizationStateReady' ||
              expectedClient == null) {
            throw StateError('Telegram is not signed in.');
          }
          final account = await request({'@type': 'getMe'});
          final id = account['id'];
          if (id is! int || id <= 0) {
            throw StateError('Telegram account could not be verified.');
          }
          final sessions = store ?? TelegramSessionStore();
          final session = await sessions.verifyOwner(id);
          if (_clientId != expectedClient ||
              authorizationState != 'authorizationStateReady') {
            throw StateError('Telegram session changed during verification.');
          }
          verifiedSessionId = session;
          notifyListeners();
          unawaited(sessions.saveProfile(session, account).catchError((_) {}));
        })().whenComplete(() {
          if (identical(_verification, operation)) _verification = null;
        });
    _verification = operation;
    return operation;
  }

  Future<void> create() async {
    if (_loggingOut) throw StateError('Telegram is signing out.');
    if (_switchingSession) throw StateError('Telegram is switching accounts.');
    await _createClient();
  }

  Future<void> _createClient() async {
    if (authorizationState == 'authorizationStateClosed') {
      _clientId = null;
      authorizationState = null;
    }
    _clientId ??= await _channel.invokeMethod<int>('create');
    if (_clientId == null) {
      throw StateError('TDLib client could not be created');
    }
    if (!_receiverStarted) {
      _receiverStarted = true;
      unawaited(_receiveLoop());
    }
  }

  /// Close the active client without logging out, then select a new slot.
  /// [prepare] must stop account-bound playback and background work first.
  /// The caller is responsible for initializing the new TDLib instance.
  Future<void> switchSession(
    String sessionId, {
    required Future<void> Function() prepare,
    TelegramSessionStore? store,
  }) async {
    if (_switchingSession || _loggingOut) {
      throw StateError('Telegram account change is already in progress.');
    }
    final sessions = store ?? TelegramSessionStore();
    // Validate before stopping the active session.
    await sessions.directoryFor(sessionId);
    if (_switchingSession || _loggingOut) {
      throw StateError('Telegram account change is already in progress.');
    }
    _switchingSession = true;
    try {
      final previous = await sessions.activeId();
      if (previous == sessionId) return;
      await prepare();
      if (_clientId != null &&
          authorizationState != 'authorizationStateClosed') {
        final closed = Completer<void>();
        void listener() {
          if (authorizationState == 'authorizationStateClosed' &&
              !closed.isCompleted) {
            closed.complete();
          }
        }

        addListener(listener);
        try {
          await request({'@type': 'close'});
          listener();
          await closed.future.timeout(const Duration(seconds: 45));
        } finally {
          removeListener(listener);
        }
      }
      _clientId = null;
      verifiedSessionId = null;
      connected = false;
      activeProxyKey = null;
      final pending = _requests.values.toList();
      _requests.clear();
      for (final request in pending) {
        if (!request.isCompleted) {
          request.completeError(StateError('Telegram account changed.'));
        }
      }
      notifyListeners();
      await sessions.select(sessionId);
      try {
        await _createClient();
      } catch (_) {
        await sessions.select(previous);
        rethrow;
      }
    } finally {
      _switchingSession = false;
    }
  }

  Future<void> logOut() async {
    if (_switchingSession) throw StateError('Telegram is switching accounts.');
    if (_loggingOut) throw StateError('Telegram is already signing out.');
    if (authorizationState != 'authorizationStateReady') {
      throw StateError('No Telegram account is signed in.');
    }
    _loggingOut = true;
    final closed = Completer<void>();
    void listener() {
      if (authorizationState == 'authorizationStateClosed' &&
          !closed.isCompleted) {
        closed.complete();
      }
    }

    addListener(listener);
    try {
      await request({'@type': 'logOut'});
      listener();
      await closed.future.timeout(const Duration(seconds: 45));
      _clientId = null;
      connected = false;
      activeProxyKey = null;
      notifyListeners();
    } finally {
      removeListener(listener);
      _loggingOut = false;
    }
  }

  Future<void> _receiveLoop() async {
    while (_receiverStarted) {
      try {
        final value = await _channel.invokeMethod<String>('receive');
        if (value != null) {
          final update = jsonDecode(value) as Map<String, dynamic>;
          final clientId = update['@client_id'];
          if (clientId is int && clientId != _clientId) continue;
          final extra = update['@extra'];
          if (update['@type'] == 'error' &&
              !(extra is String && extra.startsWith('musicgram_request_'))) {
            final code = update['code'];
            recordTelegramConnection(
              'TDLib error code: ${code is int ? code : 'unknown'}',
            );
          }
          if (extra is String) {
            _requests.remove(extra)?.complete(update);
          }
          updateConnectionInfo(update);
          updateAuthorizationInfo(update);
          // Responses to request() belong to the caller, not the global
          // update stream. Some are expected errors, such as loadChats 404.
          if (extra is String && extra.startsWith('musicgram_request_')) {
            continue;
          }
          _updates.add(update);
        }
      } catch (error, stack) {
        _updates.addError(error, stack);
        _receiverStarted = false;
      }
    }
  }

  Future<void> send(Map<String, Object?> request) async {
    final id = _clientId;
    if (id == null) throw StateError('Create the TDLib client first');
    await _channel.invokeMethod<void>('send', {
      'clientId': id,
      'request': jsonEncode(request),
    });
  }

  Future<Map<String, dynamic>> request(Map<String, Object?> request) async {
    final type = request['@type'];
    if (authorizationState == 'authorizationStateReady' &&
        !isAccountVerified &&
        !const {
          'getMe',
          'logOut',
          'close',
          'getAuthorizationState',
          'getCurrentState',
          'getProxies',
          'addProxy',
          'enableProxy',
          'disableProxy',
          'removeProxy',
          'pingProxy',
        }.contains(type)) {
      throw StateError(
        'Verify the Telegram account before accessing its data.',
      );
    }
    final id = 'musicgram_request_${_requestId++}';
    final result = Completer<Map<String, dynamic>>();
    _requests[id] = result;
    try {
      await send({...request, '@extra': id});
      final response = await result.future.timeout(const Duration(seconds: 30));
      if (response['@type'] == 'error') {
        if (request['@type'] == 'downloadFile' ||
            request['@type'] == 'getFileDownloadedPrefixSize') {
          final code = response['code'];
          final message = response['message'];
          final normalized = message is String
              ? message.trim().toLowerCase()
              : '';
          final reason = switch (normalized) {
            'invalid file id' ||
            'invalid file identifier' ||
            'wrong file identifier specified' => 'invalid_file_id',
            'file download has failed or was canceled' ||
            'file download has failed or was cancelled' =>
              'download_failed_or_cancelled',
            'file can\'t be downloaded' ||
            'file cannot be downloaded' => 'file_not_downloadable',
            'file_reference_expired' ||
            'file_reference_invalid' => 'file_reference_expired',
            _ => 'other',
          };
          TelegramPlaybackLog.record(
            'TDLib ${request['@type']} failed code=${code is int ? code : 'unknown'} reason=$reason',
          );
        }
        throw TdlibRequestException(
          response['code'] is int ? response['code'] as int : null,
          response['message']?.toString() ?? 'Telegram request failed',
        );
      }
      return response;
    } finally {
      _requests.remove(id);
    }
  }

  Future<Map<String, dynamic>?> receive() async {
    try {
      return await _updates.stream.first.timeout(const Duration(seconds: 1));
    } on TimeoutException {
      return null;
    }
  }
}
