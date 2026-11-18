import 'dart:io';

import 'package:flutter/gestures.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/embedded_artwork.dart';
import 'package:musicgram/lyrics_sheet.dart';
import 'package:musicgram/main.dart';
import 'package:musicgram/playback_controller.dart';

import 'fake_audio_backend.dart';

void main() {
  testWidgets('selected background is painted inside the scrolling queue', (
    tester,
  ) async {
    final player = PlaybackController(backend: FakeAudioBackend());
    addTearDown(player.dispose);
    await player.loadQueue(
      List.generate(
        30,
        (i) => LocalTrack(name: 'Queue $i', path: '/scroll-$i'),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          linuxDesktop: true,
          leftHanded: false,
          onHandChanged: (_) {},
          playbackController: player,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final list = find.byWidgetPredicate(
      (widget) => widget is ListView && widget.itemExtent == 72,
    );
    final location = tester.getCenter(list);
    await tester.sendEventToBinding(
      PointerScrollEvent(position: location, scrollDelta: const Offset(0, 45)),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    final controller = tester.widget<ListView>(list).controller!;
    expect(controller.offset, closeTo(45, .5));
    await player.playTrackAt(1);
    await tester.pump();
    final tile = find
        .ancestor(
          of: find.text('Queue 1').last,
          matching: find.byType(ListTile),
        )
        .first;
    final material = find
        .ancestor(of: tile, matching: find.byType(Material))
        .first;
    expect(find.ancestor(of: material, matching: list), findsOneWidget);
  });

  testWidgets('selected queue text contrasts with its background', (
    tester,
  ) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final player = PlaybackController(backend: FakeAudioBackend());
      await player.loadQueue(const [
        LocalTrack(name: 'Contrast song', path: '/contrast'),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.pink,
              brightness: brightness,
            ),
          ),
          home: PlayerScreen(
            linuxDesktop: true,
            leftHanded: false,
            onHandChanged: (_) {},
            playbackController: player,
          ),
        ),
      );
      final tile = tester.widget<ListTile>(
        find
            .ancestor(
              of: find.text('Contrast song').last,
              matching: find.byType(ListTile),
            )
            .first,
      );
      final a = tile.selectedColor!.computeLuminance();
      final b = tile.selectedTileColor!.computeLuminance();
      final ratio = (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05);
      expect(ratio, greaterThanOrEqualTo(4.5));
      await tester.pumpWidget(const SizedBox());
      player.dispose();
    }
  });

  testWidgets('desktop queue follows a newly playing track', (tester) async {
    final player = PlaybackController(backend: FakeAudioBackend());
    addTearDown(player.dispose);
    await player.loadQueue(
      List.generate(30, (i) => LocalTrack(name: 'Track $i', path: '/track-$i')),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          linuxDesktop: true,
          leftHanded: false,
          onHandChanged: (_) {},
          playbackController: player,
        ),
      ),
    );
    await tester.pump();
    await player.playTrackAt(25);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.text('Track 25'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('desktop source switches stay in the player panel', (
    tester,
  ) async {
    final player = PlaybackController(backend: FakeAudioBackend());
    addTearDown(player.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          linuxDesktop: true,
          leftHanded: false,
          onHandChanged: (_) {},
          playbackController: player,
        ),
      ),
    );
    await tester.tap(find.text('Telegram'));
    await tester.pump();
    expect(find.text('Telegram music'), findsWidgets);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(find.text('Local').first);
    await tester.pump();
    expect(find.text('Local music'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('desktop exposes lyrics and highlights shuffle and repeat', (
    tester,
  ) async {
    final player = PlaybackController(backend: FakeAudioBackend());
    addTearDown(player.dispose);
    await player.loadQueue(const [
      LocalTrack(name: 'Song', path: '/test-song'),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          linuxDesktop: true,
          leftHanded: false,
          onHandChanged: (_) {},
          playbackController: player,
        ),
      ),
    );
    final shuffle = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Shuffle',
    );
    final before = tester.widget<IconButton>(shuffle).color;
    await tester.tap(shuffle);
    await tester.pump();
    expect(player.shuffle, isTrue);
    expect(tester.widget<IconButton>(shuffle).color, isNot(before));
    final repeat = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Repeat',
    );
    final repeatBefore = tester.widget<IconButton>(repeat).color;
    await tester.tap(repeat);
    await tester.pump();
    expect(player.repeat, isTrue);
    expect(tester.widget<IconButton>(repeat).color, isNot(repeatBefore));
    await tester.tap(find.byTooltip('Current track actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lyrics'));
    await tester.pump();
    expect(find.byType(LyricsSheet), findsOneWidget);
  });

  test('Linux requests artwork from the native library bridge', () async {
    if (!Platform.isLinux) return;
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('musicgram/library');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'artwork') return Uint8List.fromList([1, 2, 3]);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    expect(await EmbeddedArtwork.load('/linux-artwork-test.mp3'), [1, 2, 3]);
  });
}
