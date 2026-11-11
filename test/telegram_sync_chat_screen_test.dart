import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/telegram_sync_chat_screen.dart';

import 'dart:io';

import 'package:musicgram/telegram_sync_selection.dart';

void main() {
  testWidgets('groups chats and returns selected IDs', (tester) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('telegram_selection'),
    ))!;
    addTearDown(() => directory.delete(recursive: true));
    Future<Map<String, dynamic>> request(Map<String, Object?> request) async {
      switch (request['@type']) {
        case 'loadChats':
          throw StateError('Not Found');
        case 'getChats':
          return {
            'chat_ids': [1, 2, 3, 42],
          };
        case 'getMe':
          return {'id': 42};
        case 'getChat':
          final id = request['chat_id'] as int;
          return {
            'title': id == 42
                ? 'My account'
                : ['Alice', 'News', 'Helper'][id - 1],
            'type': id == 2
                ? {'@type': 'chatTypeSupergroup', 'is_channel': true}
                : {'@type': 'chatTypePrivate', 'user_id': id},
          };
        case 'getUser':
          return {
            'type': {
              '@type': request['user_id'] == 3
                  ? 'userTypeBot'
                  : 'userTypeRegular',
            },
          };
        default:
          throw StateError('unexpected request');
      }
    }

    final store = TelegramSyncSelection(
      request: request,
      directory: () async => directory,
    );
    await tester.runAsync(() => store.save({1}));
    Set<int>? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await Navigator.push<Set<int>>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TelegramSyncChatScreen(
                      request: request,
                      selection: store,
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    for (var i = 0; i < 30 && find.text('Alice').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Saved Messages'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Saved Messages')).dy,
      lessThan(tester.getTopLeft(find.text('Alice')).dy),
    );
    await tester.enterText(find.byType(TextField), 'alice');
    await tester.pump();
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Saved Messages'), findsNothing);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, 'Alice'),
          )
          .value,
      isTrue,
    );
    await tester.tap(find.text('Select all'));
    await tester.pump();
    expect(find.text('4 selected'), findsOneWidget);
    await tester.tap(find.text('Sync selected chats'));
    await tester.pump();
    for (var i = 0; i < 30 && selected == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(selected, {1, 2, 3, 42});
    expect(await tester.runAsync(store.load), {1, 2, 3, 42});
  });
}
