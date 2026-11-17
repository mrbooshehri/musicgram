import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/embedded_artwork.dart';
import 'package:musicgram/lyrics_sheet.dart';
import 'package:musicgram/main.dart';
import 'package:musicgram/playback_controller.dart';

import 'fake_audio_backend.dart';

void main() {
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
    await tester.tap(find.byTooltip('Lyrics'));
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
