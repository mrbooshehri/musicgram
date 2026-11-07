import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/upnp_discovery.dart';
import 'package:musicgram/upnp_discovery_screen.dart';
import 'package:musicgram/playback_controller.dart';

import 'fake_audio_backend.dart';
import 'cast_playback_test.dart' show FakeCast;

void main() {
  testWidgets('Telegram tracks can be sent to a renderer', (tester) async {
    final player = PlaybackController(backend: FakeAudioBackend());
    addTearDown(player.dispose);
    await player.loadQueue(const [
      LocalTrack(
        name: 'song.mp3',
        path: 'http://127.0.0.1:1234/token/song',
        telegramFileId: 42,
      ),
    ]);
    final cast = FakeCast();
    await tester.pumpWidget(
      MaterialApp(
        home: UpnpDiscoveryScreen(
          player: player,
          discover: () async => [
            const UpnpRenderer(id: 'tv', name: 'TV', canPlay: true),
          ],
          prepare: (_, track, _) async {
            expect(track.telegramFileId, 42);
            return cast;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('TV'));
    await tester.pumpAndSettle();
    expect(find.text('Casting to TV'), findsOneWidget);
    expect(cast.plays, 1);
    await player.stopCasting();
  });
  testWidgets('shows progress and discovered renderer', (tester) async {
    final result = Completer<List<UpnpRenderer>>();
    await tester.pumpWidget(
      MaterialApp(home: UpnpDiscoveryScreen(discover: () => result.future)),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    result.complete([
      const UpnpRenderer(id: '1', name: 'Living room TV', canPlay: true),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Living room TV'), findsOneWidget);
    expect(find.text('Choose a UPnP/DLNA device'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
  testWidgets('shows empty and failure states with retry', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: UpnpDiscoveryScreen(
          discover: () async {
            calls++;
            if (calls == 1) return [];
            throw StateError('network');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No compatible devices found.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Could not scan for devices.'), findsOneWidget);
  });
  testWidgets('selecting a device starts and stops casting', (tester) async {
    final player = PlaybackController(backend: FakeAudioBackend());
    addTearDown(player.dispose);
    await player.loadQueue(const [LocalTrack(name: 'song', path: '/song.mp3')]);
    final cast = FakeCast();
    await tester.pumpWidget(
      MaterialApp(
        home: UpnpDiscoveryScreen(
          player: player,
          discover: () async => [
            const UpnpRenderer(id: 'tv', name: 'TV', canPlay: true),
          ],
          prepare: (_, _, _) async => cast,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('TV'));
    await tester.pumpAndSettle();
    expect(find.text('Casting to TV'), findsOneWidget);
    expect(cast.plays, 1);
    await tester.tap(find.text('Stop casting'));
    await tester.pumpAndSettle();
    expect(cast.closes, 1);
    expect(player.isCasting, isFalse);
  });
  testWidgets('refresh scans again when devices already exist', (tester) async {
    var scans = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: UpnpDiscoveryScreen(
          discover: () async {
            scans++;
            return [
              UpnpRenderer(id: '$scans', name: 'Device $scans', canPlay: true),
            ];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Device 1'), findsOneWidget);
    await tester.tap(find.byTooltip('Refresh devices'));
    await tester.pumpAndSettle();
    expect(find.text('Device 2'), findsOneWidget);
  });
  testWidgets(
    'play on this device closes the receiver and resumes local audio',
    (tester) async {
      final backend = FakeAudioBackend();
      final player = PlaybackController(backend: backend);
      addTearDown(player.dispose);
      await player.loadQueue(const [
        LocalTrack(name: 'song', path: '/song.mp3'),
      ]);
      final cast = FakeCast();
      await player.startCasting(cast);
      await tester.pumpWidget(
        MaterialApp(
          home: UpnpDiscoveryScreen(player: player, discover: () async => []),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play on this device'));
      await tester.pumpAndSettle();
      expect(cast.closes, 1);
      expect(player.isCasting, isFalse);
      expect(player.isPlaying, isTrue);
      expect(backend.playCount, 2);
    },
  );
}
