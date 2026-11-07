import 'package:flutter/material.dart';

import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/telegram_music_library.dart';
import 'package:musicgram/telegram_playlists_screen.dart';

void main() {
  testWidgets(
    'Telegram all songs and artist categories use selected cached tracks',
    (tester) async {
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('telegram_categories'),
      ))!;
      addTearDown(() => dir.delete(recursive: true));
      await tester.runAsync(() async {
        await File('${dir.path}/telegram_sync_selection_1.json')
            .writeAsString('[1,2]');
        await File('${dir.path}/telegram_music_1.json').writeAsString(
          jsonEncode({
            'complete': true,
            'groups': {
              '1': [
                {
                  'chat_id': 1,
                  'id': 1,
                  'content': {
                    '@type': 'messageAudio',
                    'audio': {'title': 'First song', 'performer': 'Artist A'},
                  },
                },
              ],
              '2': [
                {
                  'chat_id': 2,
                  'id': 2,
                  'content': {
                    '@type': 'messageAudio',
                    'audio': {'title': 'Second song', 'performer': 'Artist B'},
                  },
                },
              ],
            },
          }),
        );
      });
      Future<Map<String, dynamic>> request(Map<String, Object?> req) async {
        if (req['@type'] == 'getMe') return {'id': 1};
        return {};
      }

      Future<void> waitFor(String name) async {
        for (var i = 0; i < 40 && find.text(name).evaluate().isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
      }

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 600,
            child: TelegramPlaylistsScreen(
              sheetMode: true,
              category: 'All songs',
              request: request,
              cacheDirectory: () async => dir,
            ),
          ),
        ),
      );
      await waitFor('First song');
      expect(find.text('First song'), findsOneWidget);
      expect(find.text('Second song'), findsOneWidget);
      expect(find.text('All songs'), findsNothing);
      expect(find.byTooltip('Back'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 600,
            child: TelegramPlaylistsScreen(
              key: const ValueKey('artists'),
              sheetMode: true,
              category: 'Artists',
              request: request,
              cacheDirectory: () async => dir,
            ),
          ),
        ),
      );
      await waitFor('Artist A');
      expect(find.text('Artist B'), findsOneWidget);
      await tester.tap(find.text('Artist A'));
      await tester.pump();
      expect(find.text('First song'), findsOneWidget);
      expect(find.text('Second song'), findsNothing);
      expect(find.byTooltip('Back'), findsOneWidget);
    },
  );
  testWidgets('Telegram sheet shows skeleton while cached data is loading', (
    tester,
  ) async {
    final getMe = Completer<Map<String, dynamic>>();
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('telegram_sheet_loading'),
    ))!;
    addTearDown(() => directory.delete(recursive: true));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: TelegramPlaylistsScreen(
              sheetMode: true,
              request: (request) =>
                  request['@type'] == 'getMe' ? getMe.future : Future.value({}),
              cacheDirectory: () async => directory,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('libraryLoadingSkeleton')), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    getMe.complete({'id': 1});
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  });
  testWidgets('Telegram playlist and track navigation stays in sheets', (
    tester,
  ) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('telegram_sheet_test'),
    ))!;
    addTearDown(() => directory.delete(recursive: true));
    final track = {
      'chat_id': 1,
      'id': 2,
      'content': {
        '@type': 'messageAudio',
        'audio': {'title': 'Sheet song', 'performer': 'Artist'},
      },
    };
    await tester.runAsync(() async {
      await File('${directory.path}/telegram_sync_selection_1.json')
          .writeAsString('[1]');
      await File('${directory.path}/telegram_music_1.json').writeAsString(
        jsonEncode({
          'complete': true,
          'groups': {
            '1': [track],
          },
        }),
      );
      await File('${directory.path}/playlists.json').writeAsString(
        jsonEncode([
          {
            'type': 'telegram',
            'name': 'Saved list',
            'tracks': [track],
          },
        ]),
      );
    });
    var searches = 0;
    Future<Map<String, dynamic>> request(Map<String, Object?> req) async {
      if (req['@type'] == 'getMe') return {'id': 1};
      if (req['@type'] == 'getChat') return {'title': 'Chat list'};
      searches++;
      return {};
    }

    final playing = Completer<void>();
    var selected = false;
    var local = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => SizedBox(
                  height: MediaQuery.sizeOf(context).height * .8,
                  child: TelegramPlaylistsScreen(
                    sheetMode: true,
                    request: request,
                    cacheDirectory: () async => directory,
                    onOpenLocal: () => local = true,
                    onPlay: (tracks, index, name) {
                      selected = true;
                      return playing.future;
                    },
                  ),
                ),
              ),
              child: const Text('Open Telegram'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open Telegram'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final originalSheet = tester.element(find.byType(BottomSheet));
    for (
      var i = 0;
      i < 40 &&
          (find.text('Saved list').evaluate().isEmpty ||
              find.text('Chat list').evaluate().isEmpty);
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text('Telegram'), findsOneWidget);
    expect(find.text('Telegram playlists'), findsNothing);
    expect(find.text('Your playlists'), findsNothing);
    expect(find.byTooltip('Back'), findsNothing);
    expect(searches, 0);
    await tester.tap(find.text('Local'));
    expect(local, isTrue);
    await tester.enterText(find.byType(TextField), 'cht lst');
    await tester.pump();
    expect(find.text('Saved list'), findsNothing);
    expect(find.text('Chat list'), findsOneWidget);
    await tester.tap(find.text('Chat list'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'sht sng');
    await tester.pump();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.element(find.byType(BottomSheet)), same(originalSheet));
    expect(find.text('Sheet song'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Saved list'), findsOneWidget);
    await tester.tap(find.text('Saved list'));
    await tester.pump();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.element(find.byType(BottomSheet)), same(originalSheet));
    expect(find.text('Sheet song'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Saved list'), findsOneWidget);
    await tester.tap(find.text('Saved list'));
    await tester.pump();
    await tester.tap(find.text('Sheet song'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(selected, isTrue);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Open Telegram'), findsOneWidget);
    playing.complete();
    await tester.pump();
  });
  testWidgets('shows selected cached playlist and its tracks', (tester) async {
    var switched = false;
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('telegram_playlist_test'),
    ))!;
    addTearDown(() => directory.delete(recursive: true));
    await tester.runAsync(() async {
      await File('${directory.path}/telegram_sync_selection_1.json')
          .writeAsString('[1]');
      await File('${directory.path}/telegram_music_1.json').writeAsString(
        jsonEncode({
          'complete': true,
          'groups': {
            '1': [
              {
                'chat_id': 1,
                'id': 2,
                'content': {
                  '@type': 'messageAudio',
                  'audio': {'title': 'A song', 'performer': 'An artist'},
                },
              },
            ],
          },
        }),
      );
    });
    Future<Map<String, dynamic>> request(Map<String, Object?> request) async {
      if (request['@type'] == 'getMe') return {'id': 1};
      if (request['@type'] == 'getChat') return {'title': 'My music'};
      final filter = request['filter'] as Map;
      return {
        'messages': filter['@type'] == 'searchMessagesFilterAudio'
            ? [
                {
                  'chat_id': 1,
                  'id': 2,
                  'content': {
                    '@type': 'messageAudio',
                    'audio': {'title': 'A song', 'performer': 'An artist'},
                  },
                },
              ]
            : [],
        'next_offset': '',
      };
    }

    await tester.pumpWidget(
      MaterialApp(
        home: TelegramPlaylistsScreen(
          library: TelegramMusicLibrary(request: request),
          request: request,
          cacheDirectory: () async => directory,
          onOpenLocal: () => switched = true,
        ),
      ),
    );
    await tester.tap(find.text('Local'));
    expect(switched, isTrue);
    for (var i = 0; i < 40; i++) {
      await tester.pump();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      if (find.text('1 track').evaluate().isNotEmpty) break;
    }
    await tester.pumpAndSettle();
    expect(find.text('My music'), findsOneWidget);
    expect(find.text('1 track'), findsOneWidget);
    await tester.tap(find.text('My music'));
    await tester.pumpAndSettle();
    expect(find.text('A song'), findsOneWidget);
    expect(find.text('An artist'), findsOneWidget);
  });
}
