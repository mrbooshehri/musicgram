import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/playlist_settings_screen.dart';

void main() {
  testWidgets(
    'deleting a playlist preserves the music and persists the change',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('playlist_delete'),
      ))!;
      addTearDown(() => directory.delete(recursive: true));
      final music = File('${directory.path}/song.mp3');
      await tester.runAsync(() async {
        await music.writeAsString('audio');
        await File('${directory.path}/playlists.json').writeAsString(
          jsonEncode([
            {
              'name': 'Favorites',
              'type': 'local',
              'tracks': [
                {'name': 'Song', 'path': music.path},
              ],
            },
          ]),
        );
      });
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => directory.path);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(
        const MaterialApp(home: PlaylistSettingsScreen()),
      );
      for (
        var i = 0;
        i < 30 && find.text('Favorites').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.tap(find.byTooltip('Delete playlist'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Favorites'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete playlist'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      for (
        var i = 0;
        i < 30 && find.text('No playlists yet.').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.text('No playlists yet.'), findsOneWidget);
      expect(await tester.runAsync(music.exists), isTrue);
      final saved = await tester.runAsync(
        () => File('${directory.path}/playlists.json').readAsString(),
      );
      expect(jsonDecode(saved!), isEmpty);
    },
  );
  testWidgets('playlist track starts without leaving playlist management', (
    tester,
  ) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('playlist_navigation'),
    ))!;
    addTearDown(() => directory.delete(recursive: true));
    await tester.runAsync(
      () => File('${directory.path}/playlists.json').writeAsString(
        jsonEncode([
          {
            'name': 'Favorites',
            'type': 'local',
            'tracks': [
              {'name': 'My song', 'path': '/song'},
            ],
          },
        ]),
      ),
    );
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => directory.path);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final preparation = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => PlaylistSettingsScreen(
                    onPlay: (_, _) => preparation.future,
                  ),
                ),
              ),
              child: const Text('Player screen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Player screen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 30 && find.text('Favorites').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My song'));
    await tester.pumpAndSettle();
    expect(find.text('My song'), findsOneWidget);
    expect(find.text('Player screen'), findsNothing);
    expect(preparation.isCompleted, isFalse);
    preparation.completeError(StateError('unavailable'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Could not play track:'), findsOneWidget);
  });
  testWidgets('Telegram playlist editor restores the session when opened', (
    tester,
  ) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('playlist_session'),
    ))!;
    addTearDown(() => directory.delete(recursive: true));
    await tester.runAsync(
      () => File('${directory.path}/playlists.json').writeAsString(
        jsonEncode([
          {'name': 'Telegram mix', 'type': 'telegram', 'tracks': []},
        ]),
      ),
    );
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => directory.path);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    var restored = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PlaylistSettingsScreen(
          ensureTelegramSession: () async {
            restored++;
            return false;
          },
        ),
      ),
    );
    for (
      var i = 0;
      i < 30 && find.text('Telegram mix').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.tap(find.text('Telegram mix'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add music'));
    await tester.pumpAndSettle();
    expect(restored, 1);
    expect(
      find.textContaining('Could not connect to Telegram'),
      findsOneWidget,
    );
  });
}
