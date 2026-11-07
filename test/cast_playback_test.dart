import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/playback_controller.dart';

import 'fake_audio_backend.dart';

class FakeCast implements RemotePlaybackSession {
  @override
  String get deviceName => 'TV';
  int plays = 0;
  int pauses = 0;
  int closes = 0;
  Duration? sought;
  @override
  bool get supportsVolume => true;
  LocalTrack? loaded;
  Object? loadError;
  double remoteVolume = .5;
  Duration remotePosition = Duration.zero;
  String remoteState = 'PLAYING';
  @override
  Future<String?> readPlaybackState() async => remoteState;
  @override
  Future<void> loadTrack(LocalTrack track) async {
    if (loadError != null) throw loadError!;
    loaded = track;
  }

  @override
  Future<({Duration? position, Duration? duration})> readTiming() async =>
      (position: remotePosition, duration: const Duration(minutes: 4));
  @override
  Future<double?> readVolume() async => remoteVolume;
  @override
  Future<void> setVolume(double value) async {
    remoteVolume = value;
  }

  @override
  Future<void> seek(Duration position) async {
    sought = position;
  }

  @override
  Future<void> play() async {
    plays++;
  }

  @override
  Future<void> pause() async {
    pauses++;
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

void main() {
  testWidgets('advances when receiver finishes but not when stopped early', (
    tester,
  ) async {
    final player = PlaybackController(backend: FakeAudioBackend());
    addTearDown(player.dispose);
    await player.loadQueue(const [
      LocalTrack(name: 'one', path: '/one'),
      LocalTrack(name: 'two', path: '/two'),
    ]);
    final cast = FakeCast();
    await player.startCasting(cast);
    await tester.pump();
    cast.remotePosition = const Duration(minutes: 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    cast.remoteState = 'STOPPED';
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(cast.loaded, isNull);
    expect(player.isPlaying, isFalse);
    cast.remoteState = 'PLAYING';
    cast.remotePosition = const Duration(minutes: 3, seconds: 59);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    cast.remoteState = 'STOPPED';
    cast.remotePosition = Duration.zero;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(cast.loaded?.path, '/two');
    expect(player.currentTrack?.path, '/two');
    expect(player.isPlaying, isTrue);
    await player.stopCasting();
  });
  testWidgets(
    'repeats the same cast track after it ends when repeat is enabled',
    (tester) async {
      final player = PlaybackController(backend: FakeAudioBackend());
      addTearDown(player.dispose);
      await player.loadQueue(const [LocalTrack(name: 'one', path: '/one')]);
      player.setRepeat(true);
      final cast = FakeCast()
        ..remotePosition = const Duration(minutes: 3, seconds: 59);
      await player.startCasting(cast);
      await tester.pump();
      cast.remoteState = 'STOPPED';
      cast.remotePosition = Duration.zero;
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(cast.loaded?.path, '/one');
      expect(cast.plays, 2);
      await player.stopCasting();
    },
  );
  testWidgets(
    'polls receiver position and volume and retains track on failure',
    (tester) async {
      final player = PlaybackController(backend: FakeAudioBackend());
      addTearDown(player.dispose);
      await player.loadQueue(const [
        LocalTrack(name: 'one', path: '/one'),
        LocalTrack(name: 'two', path: '/two'),
      ]);
      final cast = FakeCast();
      await player.startCasting(cast);
      await tester.pump();
      cast.remotePosition = const Duration(seconds: 40);
      cast.remoteVolume = .7;
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(player.position, const Duration(seconds: 40));
      expect(player.duration, const Duration(minutes: 4));
      expect(player.volume, .7);
      cast.loadError = StateError('unavailable');
      await player.next();
      expect(player.currentTrack?.path, '/one');
      expect(player.errorMessage, contains('Could not change'));
      await player.stopCasting();
    },
  );
  test('stops Telegram casting before clearing account playback', () async {
    final player = PlaybackController(backend: FakeAudioBackend());
    addTearDown(player.dispose);
    await player.loadQueue(const [
      LocalTrack(name: 'Telegram', path: '/song', telegramFileId: 1),
    ]);
    final cast = FakeCast();
    await player.startCasting(cast);
    await player.clearTelegramQueue();
    expect(cast.closes, 1);
    expect(player.isCasting, isFalse);
    expect(player.queue, isEmpty);
  });
  test(
    'casting pauses local audio and routes playback controls to receiver',
    () async {
      final backend = FakeAudioBackend();
      final player = PlaybackController(backend: backend);
      final cast = FakeCast();
      addTearDown(player.dispose);
      await player.loadQueue(const [
        LocalTrack(name: 'one', path: '/one'),
        LocalTrack(name: 'two', path: '/two'),
      ]);
      await player.startCasting(cast);
      expect(player.isCasting, isTrue);
      expect(player.castDeviceName, 'TV');
      expect(backend.pauseCount, greaterThan(0));
      expect(cast.plays, 1);
      await player.pause();
      expect(cast.pauses, 1);
      expect(player.isPlaying, isFalse);
      await player.play();
      expect(cast.plays, 2);
      await player.seek(const Duration(seconds: 20));
      expect(cast.sought, const Duration(seconds: 20));
      await player.setVolume(.9);
      expect(cast.remoteVolume, .9);
      await player.next();
      expect(player.currentTrack?.path, '/two');
      expect(cast.loaded?.path, '/two');
      await player.stopCasting();
      expect(cast.closes, 1);
      expect(player.isCasting, isFalse);
      expect(player.isPlaying, isFalse);
      await player.play();
      expect(backend.playCount, 2);
    },
  );
}
