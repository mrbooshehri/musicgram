import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/playback_controller.dart';

import 'fake_audio_backend.dart';

class FakeSystemVolume implements SystemMediaVolume {
  double value = .6;
  @override
  Future<double> read() async => value;
  @override
  Future<double> set(double requested) async => value = requested;
}

void main() {
  test('pause during delayed play does not leave playback running', () async {
    final backend = FakeAudioBackend()..playGate = Completer<void>();
    final player = PlaybackController(backend: backend);
    addTearDown(player.dispose);
    final loading = player.loadQueue(const [
      LocalTrack(name: 'Telegram', path: '/telegram', telegramFileId: 1),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(player.showPauseControl, isTrue);
    await player.pause();
    expect(player.showPauseControl, isFalse);
    backend.playGate!.complete();
    await loading;
    await Future<void>.delayed(Duration.zero);
    expect(player.isPlaying, isFalse);
    expect(backend.pauseCount, 1);
  });
  test(
    'Telegram playback intent updates while the source is loading',
    () async {
      final gate = Completer<void>();
      final backend = FakeAudioBackend()..loadGate = gate;
      final player = PlaybackController(backend: backend);
      addTearDown(player.dispose);
      final loading = player.loadQueue(const [
        LocalTrack(
          name: 'Telegram',
          path: 'http://127.0.0.1/audio',
          telegramFileId: 1,
        ),
      ]);
      expect(player.isLoading, isTrue);
      expect(player.showPauseControl, isTrue);
      await player.togglePlayback();
      expect(player.showPauseControl, isFalse);
      gate.complete();
      await loading;
      expect(backend.playCount, 0);
      expect(player.isPlaying, isFalse);
    },
  );
  test('an error while loading cancels stale playback before retry', () async {
    final gate = Completer<void>();
    final backend = FakeAudioBackend()..loadGate = gate;
    final playback = PlaybackController(backend: backend);
    addTearDown(playback.dispose);
    final loading = playback.loadQueue(const [
      LocalTrack(name: 'Song', path: '/song'),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(playback.isLoading, isTrue);
    backend.positions.addError(StateError('player failure'));
    await Future<void>.delayed(Duration.zero);
    expect(playback.isLoading, isFalse);
    expect(playback.isPlaying, isFalse);
    backend.loadGate = null;
    gate.complete();
    await loading;
    expect(backend.playCount, 0);
    await playback.play();
    expect(playback.isPlaying, isTrue);
  });
  test('asynchronous player error resets playback and allows retry', () async {
    final backend = FakeAudioBackend();
    final playback = PlaybackController(backend: backend);
    addTearDown(playback.dispose);
    await playback.loadQueue(const [LocalTrack(name: 'Song', path: '/song')]);
    backend.positions.addError(StateError('player failure'));
    await Future<void>.delayed(Duration.zero);
    expect(playback.isPlaying, isFalse);
    expect(playback.isLoading, isFalse);
    expect(playback.errorMessage, contains('Tap play'));
    await playback.play();
    expect(backend.loadedSources, ['/song', '/song']);
    expect(playback.isPlaying, isTrue);
    expect(playback.errorMessage, isNull);
  });
  test(
    'system media volume is read, changed, and kept separate from player gain',
    () async {
      final backend = FakeAudioBackend();
      final system = FakeSystemVolume();
      final playback = PlaybackController(
        backend: backend,
        systemVolume: system,
      );
      addTearDown(playback.dispose);
      await playback.syncSystemVolume();
      expect(playback.volume, .6);
      await playback.loadQueue(const [LocalTrack(name: 'Song', path: '/song')]);
      expect(backend.lastVolume, 1);
      await playback.setVolume(.8);
      expect(system.value, .8);
      system.value = .4;
      await playback.syncSystemVolume();
      expect(playback.volume, .4);
    },
  );
  test('play retries loading a track after the source fails', () async {
    final backend = FakeAudioBackend()
      ..loadError = TimeoutException('slow source');
    final playback = PlaybackController(backend: backend);
    addTearDown(playback.dispose);
    await playback.loadQueue(const [LocalTrack(name: 'Song', path: '/song')]);
    expect(playback.errorMessage, isNotNull);
    backend.loadError = null;
    await playback.play();
    expect(backend.loadedSources, ['/song', '/song']);
    expect(backend.playCount, 1);
    expect(playback.isPlaying, isTrue);
  });
  late FakeAudioBackend backend;
  late PlaybackController controller;

  setUp(() {
    backend = FakeAudioBackend();
    controller = PlaybackController(backend: backend);
  });

  tearDown(() {
    controller.dispose();
  });

  test('loads a local queue and routes playback, seek, and volume', () async {
    const tracks = [
      LocalTrack(name: 'first.mp3', path: '/music/first.mp3'),
      LocalTrack(name: 'second.ogg', path: '/music/second.ogg'),
    ];

    await controller.loadQueue(tracks);
    expect(controller.currentTrack, tracks.first);
    expect(controller.isLoading, isFalse);
    expect(controller.isPlaying, isTrue);
    expect(backend.playCount, 1);

    await controller.pause();
    expect(controller.isPlaying, isFalse);
    await controller.play();
    expect(controller.isPlaying, isTrue);
    expect(backend.playCount, 2);

    backend.positions.add(const Duration(seconds: 12));
    await Future<void>.delayed(Duration.zero);
    expect(controller.position, const Duration(seconds: 12));

    backend.durations.add(const Duration(minutes: 3));
    await Future<void>.delayed(Duration.zero);
    await controller.seek(const Duration(minutes: 1));
    expect(backend.lastSeek, const Duration(minutes: 1));
    await controller.setVolume(.35);
    expect(backend.lastVolume, .35);

    await controller.pause();
    expect(controller.isPlaying, isFalse);
    expect(backend.pauseCount, 2);
  });

  test(
    'rapid skips retain only the latest selection and resume playback',
    () async {
      const tracks = [
        LocalTrack(name: 'one', path: '/one'),
        LocalTrack(name: 'two', path: '/two'),
        LocalTrack(name: 'three', path: '/three'),
        LocalTrack(name: 'four', path: '/four'),
      ];
      await controller.loadQueue(tracks);
      final gate = Completer<void>();
      backend.loadGate = gate;
      final first = controller.next();
      await Future<void>.delayed(Duration.zero);
      final second = controller.next();
      final third = controller.next();
      backend.loadGate = null;
      gate.complete();
      await Future.wait([first, second, third]);
      expect(controller.currentTrack, tracks[3]);
      expect(backend.lastSource, '/four');
      expect(backend.loadedSources, ['/one', '/two', '/four']);
      expect(controller.isPlaying, isTrue);
      expect(controller.isLoading, isFalse);
    },
  );

  test('next and previous load the adjacent local track', () async {
    const tracks = [
      LocalTrack(name: 'first.mp3', path: '/music/first.mp3'),
      LocalTrack(name: 'second.ogg', path: '/music/second.ogg'),
    ];
    await controller.loadQueue(tracks);

    await controller.next();
    expect(controller.currentTrack, tracks[1]);
    expect(backend.lastSource, '/music/second.ogg');

    await controller.previous();
    expect(controller.currentTrack, tracks[0]);
  });
  test('previous restart threshold is configurable', () async {
    final backend = FakeAudioBackend();
    final player = PlaybackController(backend: backend);
    addTearDown(player.dispose);
    await player.loadQueue(const [
      LocalTrack(name: 'A', path: '/a'),
      LocalTrack(name: 'B', path: '/b'),
    ], initialIndex: 1);
    player.previousRestartSeconds = 5;
    await player.seek(const Duration(seconds: 4));
    await player.previous();
    expect(player.currentTrack?.path, '/a');
    await player.playTrackAt(1);
    await player.seek(const Duration(seconds: 6));
    await player.previous();
    expect(player.currentTrack?.path, '/b');
    expect(backend.lastSeek, Duration.zero);
    player.previousRestartSeconds = 0;
    await player.previous();
    expect(player.currentTrack?.path, '/a');
  });
  test(
    'refreshing all songs preserves playback and drops excluded tracks',
    () async {
      final backend = FakeAudioBackend();
      final player = PlaybackController(backend: backend);
      addTearDown(player.dispose);
      const a = LocalTrack(name: 'A', path: '/a');
      const b = LocalTrack(name: 'B', path: '/b');
      await player.loadQueue(const [a, b], initialIndex: 1, allSongs: true);
      await player.seek(const Duration(seconds: 12));
      final plays = backend.playCount;
      player.refreshAllSongs(const [b]);
      expect(player.queue.map((e) => e.path), ['/b']);
      expect(player.position, const Duration(seconds: 12));
      expect(backend.playCount, plays);
      player.refreshAllSongs(const []);
      expect(player.currentTrack?.path, '/b');
      expect(player.isAllSongsQueue, isFalse);
    },
  );
  test(
    'clearing Telegram playback stops it and removes account-bound queue items',
    () async {
      final backend = FakeAudioBackend();
      final player = PlaybackController(backend: backend);
      addTearDown(player.dispose);
      await player.loadQueue(const [
        LocalTrack(name: 'Local', path: '/local'),
        LocalTrack(
          name: 'Telegram',
          path: 'http://127.0.0.1/track',
          telegramFileId: 2,
        ),
      ], initialIndex: 1);
      await player.clearTelegramQueue();
      expect(backend.pauseCount, 1);
      expect(player.queue.map((t) => t.path), ['/local']);
      expect(player.isPlaying, false);
    },
  );
  test('clearing Telegram tracks preserves current local playback', () async {
    final backend = FakeAudioBackend();
    final player = PlaybackController(backend: backend);
    addTearDown(player.dispose);
    await player.loadQueue(const [
      LocalTrack(name: 'Local', path: '/local'),
      LocalTrack(name: 'Telegram', path: '/telegram', telegramFileId: 2),
    ]);
    await player.seek(const Duration(seconds: 10));
    await player.clearTelegramQueue();
    expect(player.currentTrack?.path, '/local');
    expect(player.position, const Duration(seconds: 10));
    expect(player.isPlaying, isTrue);
    expect(backend.pauseCount, 0);
  });
}
