import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:musicgram/playback_controller.dart';

class FakeAudioBackend implements AudioBackend {
  final states = StreamController<PlayerState>.broadcast();
  final positions = StreamController<Duration>.broadcast();
  final durations = StreamController<Duration>.broadcast();
  final completions = StreamController<void>.broadcast();

  Completer<void>? loadGate;
  Completer<void>? playGate;
  Object? loadError;
  final List<String> loadedSources = [];
  String? lastSource;
  Duration? lastSeek;
  double? lastVolume;
  int playCount = 0;
  int pauseCount = 0;

  @override
  Stream<PlayerState> get stateChanges => states.stream;
  @override
  Stream<Duration> get positionChanges => positions.stream;
  @override
  Stream<Duration> get durationChanges => durations.stream;
  @override
  Stream<void> get completed => completions.stream;

  @override
  Future<void> load(String path) async {
    loadedSources.add(path);
    if (loadError != null) throw loadError!;
    final gate = loadGate;
    if (gate != null) await gate.future;
    lastSource = path;
  }

  @override
  Future<void> play() async {
    playCount++;
    await playGate?.future;
    states.add(PlayerState.playing);
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    states.add(PlayerState.paused);
  }

  @override
  Future<void> seek(Duration position) async => lastSeek = position;
  @override
  Future<void> setVolume(double value) async => lastVolume = value;
  @override
  Future<void> dispose() async {
    await states.close();
    await positions.close();
    await durations.close();
    await completions.close();
  }
}
