import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/telegram_playlist_picker.dart';

void main() {
  testWidgets('retains existing tracks when Telegram is not signed in', (
    tester,
  ) async {
    final tracks = <Map<String, dynamic>>[
      {'chat_id': 1, 'id': 4},
      {'chat_id': 2, 'id': 4},
    ];
    List<Map<String, dynamic>>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await Navigator.push<List<Map<String, dynamic>>>(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      TelegramPlaylistPicker(name: 'Mix', initial: tracks),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to Telegram in Settings first.'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, tracks);
  });
  testWidgets(
    'groups chats, searches tracks, and keeps selections across chats',
    (tester) async {
      final songs = List.generate(
        20000,
        (i) => <String, dynamic>{
          'chat_id': 1,
          'id': i + 1,
          'content': {
            'audio': {'title': 'Song $i', 'performer': 'Artist'},
          },
        },
      );
      final other = <String, dynamic>{
        'chat_id': 2,
        'id': 1,
        'content': {
          'audio': {'title': 'Other song'},
        },
      };
      List<Map<String, dynamic>>? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => saved = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TelegramPlaylistPicker(
                    name: 'Mix',
                    initial: const [],
                    groups: Stream.value({
                      1: songs,
                      2: [other],
                    }),
                    request: (query) async => {
                      'title': query['chat_id'] == 1
                          ? 'Big chat'
                          : 'Other chat',
                    },
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Big chat'), findsOneWidget);
      expect(find.text('Song 0'), findsNothing);
      await tester.enterText(find.byType(TextField), 'bg cht');
      await tester.pump();
      expect(find.text('Other chat'), findsNothing);
      await tester.tap(find.text('Big chat'));
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile).evaluate().length, lessThan(30));
      await tester.enterText(find.byType(TextField), 'song 19999');
      await tester.pump();
      await tester.tap(find.text('Song 19999'));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other chat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other song'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved?.map((item) => '${item['chat_id']}:${item['id']}'), [
        '1:20000',
        '2:1',
      ]);
    },
  );
  testWidgets('shows skeleton while library and chat names load', (
    tester,
  ) async {
    final groups = StreamController<Map<int, List<Map<String, dynamic>>>>();
    final title = Completer<Map<String, dynamic>>();
    addTearDown(groups.close);
    await tester.pumpWidget(
      MaterialApp(
        home: TelegramPlaylistPicker(
          name: 'Mix',
          initial: const [],
          groups: groups.stream,
          request: (_) => title.future,
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('libraryLoadingSkeleton')), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    groups.add({
      1: [
        {'id': 1, 'chat_id': 1},
      ],
    });
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('libraryLoadingSkeleton')), findsNothing);
    expect(find.byKey(const ValueKey('chat-title-loading-1')), findsOneWidget);
    expect(find.text('Loading chat…'), findsNothing);
    title.complete({'title': 'Music chat'});
    await tester.pump();
    await tester.pump();
    expect(find.text('Music chat'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-title-loading-1')), findsNothing);
  });
  testWidgets('restores Telegram session before loading playlists', (
    tester,
  ) async {
    final restoring = Completer<bool>();
    var calls = 0;
    final groups = StreamController<Map<int, List<Map<String, dynamic>>>>();
    addTearDown(groups.close);
    await tester.pumpWidget(
      MaterialApp(
        home: TelegramPlaylistPicker(
          name: 'Mix',
          initial: const [],
          groups: groups.stream,
          ensureSession: () {
            calls++;
            return restoring.future;
          },
          request: (_) async => {'title': 'Music chat'},
        ),
      ),
    );
    await tester.pump();
    expect(calls, 1);
    expect(find.byKey(const Key('libraryLoadingSkeleton')), findsOneWidget);
    expect(find.text('Sign in to Telegram in Settings first.'), findsNothing);
    restoring.complete(true);
    await tester.pump();
    groups.add({
      1: [
        {'id': 1, 'chat_id': 1},
      ],
    });
    await tester.pump();
    await tester.pump();
    expect(find.text('Music chat'), findsOneWidget);
  });
  testWidgets('shows useful message if Telegram session cannot be restored', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TelegramPlaylistPicker(
          name: 'Mix',
          initial: const [],
          ensureSession: () async => false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.textContaining('Could not connect to Telegram'),
      findsOneWidget,
    );
    expect(find.text('Save'), findsOneWidget);
  });
}
