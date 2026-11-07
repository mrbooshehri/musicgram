import 'package:flutter/material.dart';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/mini_player.dart';
import 'package:musicgram/playback_controller.dart';

import 'fake_audio_backend.dart';

void main() {
  testWidgets('mini-player shows embedded artwork for a Telegram track', (
    tester,
  ) async {
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    final backend = FakeAudioBackend();
    final player = PlaybackController(backend: backend);
    final notifier = ValueNotifier<PlaybackController?>(player);
    final secondary = ValueNotifier<bool>(true);
    addTearDown(() {
      player.dispose();
      notifier.dispose();
      secondary.dispose();
    });
    await player.loadQueue(const [
      LocalTrack(
        name: 'Telegram song',
        path: '/telegram.mp3',
        telegramFileId: 1,
        telegramMessage: {
          'content': {'@type': 'messageAudio', 'audio': {}},
        },
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MiniPlayerShell(
          player: notifier,
          secondaryPage: secondary,
          onOpenPlayer: () {},
          artworkLoader: (_) async => bytes,
          child: child!,
        ),
        home: const Scaffold(),
      ),
    );
    await tester.pumpAndSettle();
    final image = tester.widget<Image>(
      find
          .descendant(
            of: find.byKey(const Key('miniPlayer')),
            matching: find.byType(Image),
          )
          .first,
    );
    expect(image.image, isA<MemoryImage>());
  });
  testWidgets(
    'mini-player follows navigation and playback and can be dismissed',
    (tester) async {
      final backend = FakeAudioBackend();
      final player = PlaybackController(backend: backend);
      final playerNotifier = ValueNotifier<PlaybackController?>(player);
      final observer = MiniPlayerNavigatorObserver();
      final navigator = GlobalKey<NavigatorState>();
      addTearDown(() {
        player.dispose();
        playerNotifier.dispose();
        observer.dispose();
      });
      await player.loadQueue(const [
        LocalTrack(name: 'First', path: '/1'),
        LocalTrack(name: 'Second', path: '/2'),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [observer],
          builder: (context, child) => MiniPlayerShell(
            player: playerNotifier,
            secondaryPage: observer.secondaryPage,
            onOpenPlayer: () =>
                navigator.currentState!.popUntil((route) => route.isFirst),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('Settings')),
                  ),
                ),
                child: const Text('Open settings'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('miniPlayer')), findsNothing);
      await player.pause();
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('miniPlayer')), findsNothing);
      await player.play();
      await tester.pump();
      expect(find.text('First'), findsOneWidget);
      await tester.tap(find.byKey(const Key('miniPlayPause')));
      await tester.pump();
      expect(player.isPlaying, isFalse);
      expect(find.byKey(const Key('miniPlayer')), findsOneWidget);
      await tester.tap(find.byKey(const Key('miniPlayPause')));
      await tester.pump();
      expect(player.isPlaying, isTrue);
      await tester.tap(find.byKey(const Key('miniNext')));
      await tester.pump();
      expect(find.text('Second'), findsOneWidget);
      final wasPlaying = player.isPlaying;
      await tester.tap(find.byKey(const Key('miniClose')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('miniPlayer')), findsNothing);
      expect(player.currentTrack?.name, 'Second');
      expect(player.isPlaying, wasPlaying);
      await player.playTrackAt(0);
      await tester.pumpAndSettle();
      expect(find.text('First'), findsOneWidget);
      await tester.tap(find.text('First'));
      await tester.pumpAndSettle();
      expect(find.text('Open settings'), findsOneWidget);
      expect(find.byKey(const Key('miniPlayer')), findsNothing);
    },
  );
}
