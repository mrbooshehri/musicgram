import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/telegram_account_card.dart';
import 'package:musicgram/telegram_account_profile.dart';

import 'dart:io';
import 'dart:convert';

void main() {
  testWidgets('saved account avatar displays its cached image', (tester) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('saved_avatar'),
    ))!;
    addTearDown(() => dir.delete(recursive: true));
    final photo = File('${dir.path}/profile.png');
    await tester.runAsync(
      () => photo.writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TelegramCachedProfileAvatar(path: photo.path)),
      ),
    );
    expect(find.byType(Image), findsOneWidget);
  });
  testWidgets('displays the downloaded profile image', (tester) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('telegram_avatar'),
    ))!;
    addTearDown(() => dir.delete(recursive: true));
    final photo = File('${dir.path}/profile.png');
    await tester.runAsync(
      () => photo.writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
        ),
      ),
    );
    final account = Future.value(<String, dynamic>{
      'id': 42,
      'first_name': 'Sam',
      'profile_photo': {
        'small': {'id': 7},
      },
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TelegramAccountCard(
            account: account,
            connected: true,
            request: (_) async => {
              'local': {'path': photo.path, 'is_downloading_completed': true},
            },
          ),
        ),
      ),
    );
    for (var i = 0; i < 30 && find.byType(Image).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(find.byType(Image), findsOneWidget);
  });
  testWidgets('shows signed-in account and connection status', (tester) async {
    final account = Future.value(<String, dynamic>{
      'id': 1,
      'first_name': 'Sam',
      'last_name': 'Lee',
      'usernames': {
        'active_usernames': ['samlee'],
      },
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TelegramAccountCard(account: account, connected: true),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Sam Lee'), findsOneWidget);
    expect(find.text('@samlee'), findsOneWidget);
    expect(find.text('Signed in · Connected'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TelegramAccountCard(account: account, connected: false),
        ),
      ),
    );
    expect(find.text('Signed in · Connecting'), findsOneWidget);
  });
  test(
    'loads the small profile photo through TDLib and uses cached files',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'telegram_profile_photo',
      );
      addTearDown(() => dir.delete(recursive: true));
      final photo = File('${dir.path}/photo.jpg');
      await photo.writeAsBytes([1, 2, 3]);
      final user = <String, dynamic>{
        'profile_photo': {
          'small': {'id': 7},
        },
      };
      var calls = 0;
      Future<Map<String, dynamic>> request(Map<String, Object?> query) async {
        calls++;
        expect(query['@type'], 'downloadFile');
        expect(query['file_id'], 7);
        return {
          'local': {'path': photo.path, 'is_downloading_completed': true},
        };
      }

      expect(await resolveTelegramProfilePhoto(user, request), photo.path);
      user['profile_photo'] = {
        'small': {
          'id': 7,
          'local': {'path': photo.path, 'is_downloading_completed': true},
        },
      };
      expect(await resolveTelegramProfilePhoto(user, request), photo.path);
      expect(calls, 1);
    },
  );
}
