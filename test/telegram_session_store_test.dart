import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/telegram_session_store.dart';

void main() {
  test(
    'cached profile photos remain isolated and update when photos change',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'telegram_avatar_cache',
      );
      addTearDown(() => root.delete(recursive: true));
      final store = TelegramSessionStore(directory: () async => root);
      final original = File('${root.path}/first.jpg');
      await original.writeAsBytes([1, 2, 3]);
      final user = <String, dynamic>{
        'id': 123,
        'first_name': 'Sam',
        'profile_photo': {
          'id': 'photo-one',
          'small': {'id': 7},
        },
      };
      await store.verifyOwner(123);
      await store.saveProfile('legacy', user);
      await store.cacheProfilePhoto('legacy', user, original.path);
      final profile = (await store.verifiedProfiles())['legacy']!;
      expect(await File(profile.photoPath!).readAsBytes(), [1, 2, 3]);
      await store.select('session_other');
      await store.verifyOwner(456);
      await store.saveProfile('session_other', {
        'id': 456,
        'first_name': 'Alex',
      });
      await store.cacheProfilePhoto('legacy', user, original.path);
      expect(
        (await store.verifiedProfiles())['session_other']?.photoPath,
        isNull,
      );
      expect((await store.verifiedProfiles())['legacy']?.photoPath, isNotNull);
      await store.select('legacy');
      final updated = <String, dynamic>{
        'id': 123,
        'first_name': 'Sam',
        'profile_photo': {
          'id': 'photo-two',
          'small': {'id': 8},
        },
      };
      await store.saveProfile('legacy', updated);
      expect((await store.verifiedProfiles())['legacy']?.photoPath, isNull);
      await store.cacheProfilePhoto('legacy', user, original.path);
      expect((await store.verifiedProfiles())['legacy']?.photoPath, isNull);
    },
  );
  test(
    'stores display profiles only for the verified active account',
    () async {
      final root = await Directory.systemTemp.createTemp('telegram_profiles');
      addTearDown(() => root.delete(recursive: true));
      final store = TelegramSessionStore(directory: () async => root);
      await store.verifyOwner(123);
      await store.saveProfile('legacy', {
        'id': 123,
        'first_name': 'Sam',
        'last_name': 'Lee',
        'usernames': {
          'active_usernames': ['samlee'],
        },
        'phone_number': 'not-stored',
      });
      var profiles = await store.verifiedProfiles();
      expect(profiles['legacy']?.displayName, 'Sam Lee');
      expect(profiles['legacy']?.username, 'samlee');
      expect(
        await File('${root.path}/telegram_profile_legacy.json').readAsString(),
        isNot(contains('not-stored')),
      );
      await store.saveProfile('legacy', {'id': 999, 'first_name': 'Wrong'});
      profiles = await store.verifiedProfiles();
      expect(profiles['legacy']?.displayName, 'Sam Lee');
      await store.select('session_other');
      await store.verifyOwner(456);
      await store.saveProfile('session_other', {
        'id': 456,
        'first_name': 'Alex',
      });
      await store.saveProfile('legacy', {'id': 123, 'first_name': 'Stale'});
      profiles = await store.verifiedProfiles();
      expect(profiles['legacy']?.displayName, 'Sam Lee');
      expect(profiles['session_other']?.displayName, 'Alex');
    },
  );
  test(
    'new account slots do not change or overwrite the active session',
    () async {
      final root = await Directory.systemTemp.createTemp('telegram_new_slot');
      addTearDown(() => root.delete(recursive: true));
      final store = TelegramSessionStore(directory: () async => root);
      await store.verifyOwner(123);
      final first = await store.newSessionId();
      final second = await store.newSessionId();
      expect(first, isNot(second));
      expect(await store.activeId(), 'legacy');
      expect(await store.verifiedOwners(), {'legacy': 123});
      expect(await (await store.directoryFor(first)).exists(), isFalse);
    },
  );
  test(
    'keeps the legacy session path and isolates newly selected sessions',
    () async {
      final root = await Directory.systemTemp.createTemp('telegram_sessions');
      addTearDown(() => root.delete(recursive: true));
      final store = TelegramSessionStore(directory: () async => root);
      final legacy = await store.activeDirectory();
      expect(legacy.path, '${root.path}/telegram');
      await legacy.create();
      await File('${legacy.path}/marker').writeAsString('existing');
      await store.select('session_abc123');
      expect(
        (await store.activeDirectory()).path,
        '${root.path}/telegram_accounts/session_abc123',
      );
      expect(await File('${legacy.path}/marker').readAsString(), 'existing');
      expect(
        (await TelegramSessionStore(
          directory: () async => root,
        ).activeDirectory()).path,
        '${root.path}/telegram_accounts/session_abc123',
      );
      await store.select('legacy');
      expect((await store.activeDirectory()).path, legacy.path);
    },
  );

  test('rejects unsafe session identifiers', () async {
    final root = await Directory.systemTemp.createTemp('telegram_sessions');
    addTearDown(() => root.delete(recursive: true));
    final store = TelegramSessionStore(directory: () async => root);
    expect(() => store.select('../escape'), throwsArgumentError);
    await File('${root.path}/telegram_active_session.txt')
        .writeAsString('../escape');
    await expectLater(store.activeDirectory(), throwsFormatException);
  });
  test('lists only valid verified session bindings', () async {
    final root = await Directory.systemTemp.createTemp('telegram_owners');
    addTearDown(() => root.delete(recursive: true));
    final store = TelegramSessionStore(directory: () async => root);
    expect(await store.verifiedOwners(), isEmpty);
    await store.verifyOwner(123);
    await store.select('session_second');
    await store.verifyOwner(456);
    await File('${root.path}/telegram_owner_session_bad.txt')
        .writeAsString('invalid');
    await File('${root.path}/telegram_owner_invalid.txt').writeAsString('999');
    expect(await store.verifiedOwners(), {
      'legacy': 123,
      'session_second': 456,
    });
  });
  test(
    'verified user binding is stable and rejects a different user',
    () async {
      final root = await Directory.systemTemp.createTemp('telegram_owner');
      addTearDown(() => root.delete(recursive: true));
      final store = TelegramSessionStore(directory: () async => root);
      expect(await store.verifyOwner(123), 'legacy');
      expect(await store.verifyOwner(123), 'legacy');
      await expectLater(store.verifyOwner(456), throwsStateError);
      await store.select('session_second');
      expect(await store.verifyOwner(456), 'session_second');
      await expectLater(store.verifyOwner(123), throwsStateError);
      await store.select('legacy');
      expect(await store.verifyOwner(123), 'legacy');
    },
  );
}
