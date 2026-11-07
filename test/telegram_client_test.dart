import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:musicgram/telegram_session_store.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/telegram_client.dart';

void main() {
  test(
    'Telegram updating state is connected and requires an enabled proxy',
    () {
      final client = TelegramClient.forTesting();
      client.updateConnectionInfo({
        '@type': 'updateConnectionState',
        'state': {'@type': 'connectionStateUpdating'},
      });
      expect(client.connected, isTrue);
      expect(client.proxyConnected, isFalse);
      client.proxyEnabled('proxy.example:443');
      expect(client.proxyConnected, isTrue);
      client.updateConnectionInfo({
        '@type': 'updateConnectionState',
        'state': {'@type': 'connectionStateConnectingToProxy'},
      });
      expect(client.proxyConnected, isFalse);
      client.dispose();
    },
  );
  test('tracks authorization from updates and direct state responses', () {
    final client = TelegramClient.forTesting();
    var notifications = 0;
    client.addListener(() => notifications++);
    client.updateAuthorizationInfo({'@type': 'authorizationStateReady'});
    expect(client.authorizationState, 'authorizationStateReady');
    client.updateAuthorizationInfo({
      '@type': 'updateAuthorizationState',
      'authorization_state': {'@type': 'authorizationStateWaitPhoneNumber'},
    });
    expect(client.authorizationState, 'authorizationStateWaitPhoneNumber');
    expect(notifications, 2);
    client.dispose();
  });
  test(
    'proxy switch notifies listeners when ready before activation reply',
    () {
      final client = TelegramClient.forTesting();
      var notifications = 0;
      client.addListener(() => notifications++);
      client.proxySwitchStarted();
      client.updateConnectionInfo({
        '@type': 'updateConnectionState',
        'state': {'@type': 'connectionStateReady'},
      });
      client.proxyEnabled('proxy.example:443');
      expect(client.connected, isTrue);
      expect(client.activeProxyKey, 'proxy.example:443');
      expect(notifications, 3);
      client.dispose();
    },
  );
  test('tracks the enabled proxy and Telegram connection independently', () {
    final client = TelegramClient.forTesting();
    client.updateConnectionInfo({
      '@type': 'addedProxies',
      '@extra': 'proxy_status',
      'proxies': [
        {
          'is_enabled': false,
          'proxy': {'server': 'other', 'port': 443},
        },
        {
          'is_enabled': true,
          'proxy': {'server': 'active', 'port': 8443},
        },
      ],
    });
    expect(client.activeProxyKey, 'active:8443');
    expect(client.connected, isFalse);
    client.updateConnectionInfo({
      '@type': 'updateConnectionState',
      'state': {'@type': 'connectionStateReady'},
    });
    expect(client.connected, isTrue);
    client.updateConnectionInfo({
      '@type': 'updateConnectionState',
      'state': {'@type': 'connectionStateConnecting'},
    });
    expect(client.connected, isFalse);
    client.updateConnectionInfo({
      '@type': 'proxies',
      '@extra': 'proxy_status',
      'proxies': [
        {'is_enabled': true, 'server': 'legacy', 'port': 443},
      ],
    });
    expect(client.activeProxyKey, 'legacy:443');
    client.updateConnectionInfo({
      '@type': 'proxies',
      '@extra': 'proxy_status',
      'proxies': [],
    });
    expect(client.activeProxyKey, isNull);
    client.dispose();
  });
  test('logout waits for closed state before creating a new client', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('musicgram/tdlib');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final events = Queue<String>();
    Completer<String?>? pending;
    var created = 0;
    void deliver(Map<String, dynamic> event) {
      final json = jsonEncode(event);
      if (pending != null) {
        final waiter = pending!;
        pending = null;
        waiter.complete(json);
      } else {
        events.add(json);
      }
    }

    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'create') return ++created;
      if (call.method == 'receive') {
        if (events.isNotEmpty) return events.removeFirst();
        pending = Completer<String?>();
        return pending!.future;
      }
      if (call.method == 'send') {
        final request = jsonDecode(call.arguments['request'] as String) as Map;
        if (request['@type'] == 'logOut') {
          deliver({'@type': 'ok', '@extra': request['@extra']});
        }
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final client = TelegramClient.forTesting();
    await client.create();
    client.updateAuthorizationInfo({'@type': 'authorizationStateReady'});
    var finished = false;
    final logout = client.logOut().then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    deliver({
      '@client_id': 99,
      '@type': 'updateAuthorizationState',
      'authorization_state': {'@type': 'authorizationStateClosed'},
    });
    await Future<void>.delayed(Duration.zero);
    expect(client.authorizationState, 'authorizationStateReady');
    expect(finished, isFalse);
    deliver({
      '@client_id': 1,
      '@type': 'updateAuthorizationState',
      'authorization_state': {'@type': 'authorizationStateClosed'},
    });
    await logout;
    expect(client.isRunning, isFalse);
    await client.create();
    expect(created, 2);
  });
  test('unverified ready session cannot access account data', () async {
    final client = TelegramClient.forTesting();
    client.updateAuthorizationInfo({'@type': 'authorizationStateReady'});
    await expectLater(
      client.request({'@type': 'searchChats', 'query': ''}),
      throwsStateError,
    );
    expect(client.isAccountVerified, isFalse);
    client.dispose();
  });
  test('request errors are returned only to their caller', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('musicgram/tdlib');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final events = Queue<String>();
    Completer<String?>? pending;
    void deliver(Map<String, dynamic> event) {
      final value = jsonEncode(event);
      if (pending != null) {
        final waiter = pending!;
        pending = null;
        waiter.complete(value);
      } else {
        events.add(value);
      }
    }

    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'create') return 1;
      if (call.method == 'receive') {
        if (events.isNotEmpty) return events.removeFirst();
        pending = Completer<String?>();
        return pending!.future;
      }
      if (call.method == 'send') {
        final req = jsonDecode(call.arguments['request'] as String) as Map;
        deliver({
          '@client_id': 1,
          '@type': 'error',
          'code': 404,
          'message': 'Not Found',
          '@extra': req['@extra'],
        });
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final client = TelegramClient.forTesting();
    await client.create();
    final update = client.receive();
    await expectLater(client.request({'@type': 'loadChats'}), throwsStateError);
    deliver({
      '@client_id': 1,
      '@type': 'updateConnectionState',
      'state': {'@type': 'connectionStateReady'},
    });
    expect((await update)?['@type'], 'updateConnectionState');
  });
  test(
    'session switch waits for TDLib closure before selecting or creating',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final root = await Directory.systemTemp.createTemp('telegram_switch');
      final store = TelegramSessionStore(directory: () async => root);
      const channel = MethodChannel('musicgram/tdlib');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final events = Queue<String>();
      Completer<String?>? pending;
      var created = 0;
      var prepared = false;
      void deliver(Map<String, dynamic> event) {
        final encoded = jsonEncode(event);
        if (pending != null) {
          final waiter = pending!;
          pending = null;
          waiter.complete(encoded);
        } else {
          events.add(encoded);
        }
      }

      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'create') return ++created;
        if (call.method == 'receive') {
          if (events.isNotEmpty) return events.removeFirst();
          pending = Completer<String?>();
          return pending!.future;
        }
        if (call.method == 'send') {
          final request =
              jsonDecode(call.arguments['request'] as String) as Map;
          if (request['@type'] == 'close') {
            expect(prepared, isTrue);
            deliver({
              '@client_id': 1,
              '@type': 'ok',
              '@extra': request['@extra'],
            });
          }
        }
        return null;
      });
      addTearDown(() async {
        messenger.setMockMethodCallHandler(channel, null);
        await root.delete(recursive: true);
      });
      final client = TelegramClient.forTesting();
      await client.create();
      client.updateAuthorizationInfo({'@type': 'authorizationStateReady'});
      final switching = client.switchSession(
        'session_second',
        store: store,
        prepare: () async {
          prepared = true;
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(prepared, isTrue);
      expect(await store.activeId(), 'legacy');
      expect(created, 1);
      await expectLater(client.create(), throwsStateError);
      deliver({
        '@client_id': 1,
        '@type': 'updateAuthorizationState',
        'authorization_state': {'@type': 'authorizationStateClosed'},
      });
      await switching;
      expect(await store.activeId(), 'session_second');
      expect(created, 2);
      expect(client.isAccountVerified, isFalse);
    },
  );
  test('different Telegram user cannot verify an owned session', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final root = await Directory.systemTemp.createTemp('account_verify');
    final store = TelegramSessionStore(directory: () async => root);
    await store.verifyOwner(123);
    var currentUserId = 456;
    const channel = MethodChannel('musicgram/tdlib');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final events = Queue<String>();
    Completer<String?>? pending;
    void deliver(Map<String, dynamic> event) {
      final encoded = jsonEncode(event);
      if (pending != null) {
        final waiter = pending!;
        pending = null;
        waiter.complete(encoded);
      } else {
        events.add(encoded);
      }
    }

    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'create') return 1;
      if (call.method == 'receive') {
        if (events.isNotEmpty) return events.removeFirst();
        pending = Completer<String?>();
        return pending!.future;
      }
      if (call.method == 'send') {
        final request = jsonDecode(call.arguments['request'] as String) as Map;
        if (request['@type'] == 'getMe') {
          deliver({
            '@type': 'user',
            'id': currentUserId,
            '@extra': request['@extra'],
          });
        }
      }
      return null;
    });
    addTearDown(() async {
      messenger.setMockMethodCallHandler(channel, null);
      await root.delete(recursive: true);
    });
    final client = TelegramClient.forTesting();
    await client.create();
    client.updateAuthorizationInfo({'@type': 'authorizationStateReady'});
    await expectLater(client.verifyAccount(store: store), throwsStateError);
    expect(client.isAccountVerified, isFalse);
    await expectLater(client.request({'@type': 'getChats'}), throwsStateError);
    currentUserId = 123;
    await client.verifyAccount(store: store);
    expect(client.isAccountVerified, isTrue);
    expect(client.verifiedSessionId, 'legacy');
  });
}
