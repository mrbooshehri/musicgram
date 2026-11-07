import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'telegram_playback_log.dart';
import 'playback_diagnostics.dart';

abstract interface class SystemMediaVolume {
  Future<double> read();
  Future<double> set(double value);
}

class AndroidMediaVolume implements SystemMediaVolume {
  static const _channel = MethodChannel('musicgram/library');
  @override
  Future<double> read() async =>
      (await _channel.invokeMethod<double>('getMediaVolume')) ?? 0;
  @override
  Future<double> set(double value) async =>
      (await _channel.invokeMethod<double>('setMediaVolume', {
        'value': value,
      })) ??
      value;
}

@immutable
class LocalTrack {
  const LocalTrack({
    required this.name,
    required this.path,
    this.title,
    this.artist,
    this.album,
    this.genre,
    this.telegramFileId,
    this.playlistName,
    this.downloadKey,
    this.telegramMessage,
  });

  final String name;
  final String path;
  final String? title;
  final String? artist;
  final String? album;
  final String? genre;
  final int? telegramFileId;
  final String? playlistName;
  final String? downloadKey;
  final Map<String, dynamic>? telegramMessage;
  String get displayTitle =>
      title == null || title!.trim().isEmpty ? name : title!;
  String get displayArtist =>
      artist == null || artist!.trim().isEmpty || artist == '<unknown>'
      ? 'Unknown artist'
      : artist!;
}

abstract interface class AudioBackend {
  Stream<PlayerState> get stateChanges;
  Stream<Duration> get positionChanges;
  Stream<Duration> get durationChanges;
  Stream<void> get completed;

  Future<void> load(String path);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double value);
  Future<void> dispose();
}

abstract interface class RemotePlaybackSession {
  String get deviceName;
  bool get supportsVolume;
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> loadTrack(LocalTrack track);
  Future<({Duration? position, Duration? duration})> readTiming();
  Future<String?> readPlaybackState();
  Future<double?> readVolume();
  Future<void> setVolume(double value);
  Future<void> close();
}

class AudioplayersBackend implements AudioBackend {
  AudioplayersBackend([AudioPlayer? player])
    : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<PlayerState> get stateChanges => _player.onPlayerStateChanged;
  @override
  Stream<Duration> get positionChanges => _player.onPositionChanged;
  @override
  Stream<Duration> get durationChanges => _player.onDurationChanged;
  @override
  Stream<void> get completed => _player.onPlayerComplete;

  @override
  Future<void> load(String path) {
    final uri = Uri.tryParse(path);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return _player.setSource(UrlSource(path));
    }
    return _player.setSource(DeviceFileSource(path));
  }

  @override
  Future<void> play() => _player.resume();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> setVolume(double value) => _player.setVolume(value);
  @override
  Future<void> dispose() => _player.dispose();
}

class PlaybackController extends ChangeNotifier {
  PlaybackController({
    AudioBackend? backend,
    Random? random,
    SystemMediaVolume? systemVolume,
  }) : _backend = backend ?? AudioplayersBackend(),
       _systemVolume =
           systemVolume ??
           (backend == null && Platform.isAndroid
               ? AndroidMediaVolume()
               : null),
       _random = random ?? Random() {
    _subscriptions.addAll([
      _backend.stateChanges.listen(_onPlayerState, onError: _onBackendError),
      _backend.positionChanges.listen((value) {
        if (isCasting || isLoading || _seeking) return;
        position = value;
        notifyListeners();
      }, onError: _onBackendError),
      _backend.durationChanges.listen((value) {
        if (isCasting) return;
        duration = value;
        notifyListeners();
      }, onError: _onBackendError),
      _backend.completed.listen(
        (_) => unawaited(_handleCompletion()),
        onError: _onBackendError,
      ),
    ]);
    if (_systemVolume != null) {
      unawaited(syncSystemVolume());
      _volumeTimer = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => unawaited(syncSystemVolume()),
      );
    }
  }

  final AudioBackend _backend;
  int previousRestartSeconds = 3;
  final SystemMediaVolume? _systemVolume;
  Timer? _volumeTimer;
  bool _disposed = false;
  int _volumeRevision = 0;
  int _volumeWrites = 0;
  bool get usesSystemVolume => _systemVolume != null;

  Future<void> syncSystemVolume() async {
    final system = _systemVolume;
    if (system == null || _volumeWrites > 0 || isCasting) return;
    final revision = _volumeRevision;
    try {
      final current = (await system.read()).clamp(0.0, 1.0);
      if (!_disposed &&
          !isCasting &&
          _volumeWrites == 0 &&
          revision == _volumeRevision &&
          current != volume) {
        volume = current;
        notifyListeners();
      }
    } catch (_) {
      // Keep the last known volume if the platform is temporarily unavailable.
    }
  }

  final Random _random;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  List<LocalTrack> queue = const [];
  bool isAllSongsQueue = false;
  void refreshAllSongs(List<LocalTrack> tracks) {
    if (!isAllSongsQueue || isCasting) return;
    final current = currentTrack;
    final updated = List<LocalTrack>.of(tracks);
    var index = current == null
        ? -1
        : updated.indexWhere((t) => t.path == current.path);
    if (index < 0 && current != null) {
      updated.insert(0, current);
      index = 0;
      isAllSongsQueue = false;
    }
    if (updated.isEmpty) return;
    queue = List.unmodifiable(updated);
    currentIndex = index < 0 ? 0 : index;
    _chooseNext();
    notifyListeners();
  }

  void markLibraryChanged() {
    if (isAllSongsQueue) {
      isAllSongsQueue = false;
      notifyListeners();
    }
  }

  int currentIndex = 0;
  bool isLoading = false;
  bool isPlaying = false;
  bool _startingPlayback = false;
  bool get showPauseControl =>
      isLoading || _startingPlayback ? _wantsPlayback : isPlaying;
  RemotePlaybackSession? _cast;
  bool _switchingOutput = false;
  bool _changingCastTrack = false;
  bool _pollingCast = false;
  bool _castObservedPlaying = false;
  int _castRevision = 0;
  Timer? _castTimer;
  double? _localVolumeBeforeCast;
  bool get canControlCastVolume => _cast?.supportsVolume ?? false;
  bool get isCasting => _cast != null || _switchingOutput;
  String? get castDeviceName => _cast?.deviceName;

  Future<void> startCasting(RemotePlaybackSession session) async {
    if (isCasting || isLoading || currentTrack == null) {
      throw StateError('The player is not ready to start casting.');
    }
    _switchingOutput = true;
    notifyListeners();
    try {
      await pause();
      if (isPlaying) throw StateError('Could not pause local playback.');
      _localVolumeBeforeCast = volume;
      await session.play();
      _cast = session;
      _castObservedPlaying = false;
      isPlaying = true;
      errorMessage = null;
      _castRevision++;
      _castTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(_pollCast()),
      );
      unawaited(_pollCast());
    } catch (_) {
      try {
        await session.close();
      } catch (_) {
        // The receiver may already be unreachable; keep local playback paused.
      }
      rethrow;
    } finally {
      _switchingOutput = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> stopCasting() async {
    final session = _cast;
    if (session == null || _switchingOutput) return;
    _switchingOutput = true;
    _castTimer?.cancel();
    _castRevision++;
    notifyListeners();
    try {
      await session.close();
    } finally {
      _cast = null;
      _castObservedPlaying = false;
      _switchingOutput = false;
      isPlaying = false;
      final localVolume = _localVolumeBeforeCast;
      _localVolumeBeforeCast = null;
      if (localVolume != null) volume = localVolume;
      if (_systemVolume != null) unawaited(syncSystemVolume());
      notifyListeners();
    }
  }

  Future<void> _pollCast() async {
    final cast = _cast;
    if (cast == null || _pollingCast || _changingCastTrack) return;
    _pollingCast = true;
    final revision = _castRevision;
    try {
      final timing = await cast.readTiming();
      String? remoteState;
      try {
        remoteState = await cast.readPlaybackState();
      } catch (_) {
        // Some receivers do not expose transport state reliably.
      }
      if (!_disposed && identical(_cast, cast) && revision == _castRevision) {
        final previousPosition = position;
        if (timing.position != null) position = timing.position!;
        if (timing.duration != null && timing.duration! > Duration.zero) {
          duration = timing.duration!;
        }
        if (remoteState == 'PLAYING') {
          _castObservedPlaying = true;
          isPlaying = true;
        } else if (remoteState == 'PAUSED_PLAYBACK') {
          isPlaying = false;
        } else if (remoteState == 'STOPPED' && _castObservedPlaying) {
          _castObservedPlaying = false;
          final lastPosition = previousPosition > position
              ? previousPosition
              : position;
          final finished =
              isPlaying &&
              duration > Duration.zero &&
              lastPosition >= duration - const Duration(seconds: 3);
          isPlaying = false;
          if (finished) {
            unawaited(_handleCastCompletion(cast));
          }
        }
        notifyListeners();
      }
      if (cast.supportsVolume) {
        final remoteVolume = await cast.readVolume();
        if (!_disposed &&
            identical(_cast, cast) &&
            revision == _castRevision &&
            remoteVolume != null) {
          volume = remoteVolume.clamp(0.0, 1.0);
          notifyListeners();
        }
      }
    } catch (_) {
      // A receiver may temporarily reject a status request during playback.
    } finally {
      _pollingCast = false;
    }
  }

  Future<void> _handleCastCompletion(RemotePlaybackSession cast) async {
    if (!identical(_cast, cast) || queue.isEmpty) return;
    if (repeat && !shuffle) {
      await _loadCastTrack(
        queue,
        currentIndex,
        autoplay: true,
        allSongs: isAllSongsQueue,
      );
    } else if (queue.length > 1) {
      final index = shuffle
          ? (_shuffledNext ?? _nextShuffledIndex())
          : (currentIndex + 1) % queue.length;
      await _loadCastTrack(
        queue,
        index,
        autoplay: true,
        allSongs: isAllSongsQueue,
      );
    } else {
      position = duration;
      notifyListeners();
    }
  }

  Future<void> _loadCastTrack(
    List<LocalTrack> tracks,
    int index, {
    required bool autoplay,
    bool allSongs = false,
  }) async {
    final cast = _cast;
    if (cast == null || _changingCastTrack || _switchingOutput) return;
    _changingCastTrack = true;
    _castObservedPlaying = false;
    _castRevision++;
    isLoading = true;
    notifyListeners();
    try {
      await cast.loadTrack(tracks[index]);
      if (!identical(_cast, cast) || _disposed) return;
      queue = List.unmodifiable(tracks);
      currentIndex = index;
      isAllSongsQueue = allSongs;
      _sourceReady = false;
      position = Duration.zero;
      duration = Duration.zero;
      isPlaying = false;
      errorMessage = null;
      _chooseNext();
      if (autoplay) {
        await cast.play();
        if (identical(_cast, cast) && !_disposed) isPlaying = true;
      }
    } catch (error) {
      errorMessage = 'Could not change the cast track: $error';
    } finally {
      _changingCastTrack = false;
      isLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  bool _sourceReady = false;
  bool _wantsPlayback = false;
  int _loadGeneration = 0;
  Future<void> _operations = Future.value();

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _operations.then((_) => operation());
    _operations = result.catchError((_) {});
    return result;
  }

  bool repeat = false;
  bool shuffle = false;
  int? _shuffledNext;

  int? get nextIndex => queue.length < 2
      ? null
      : shuffle
      ? _shuffledNext
      : (currentIndex + 1) % queue.length;

  void _chooseNext() {
    _shuffledNext = shuffle && queue.length > 1 ? _nextShuffledIndex() : null;
  }

  double volume = .6;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  String? _errorMessage;
  String? get errorMessage => _errorMessage;
  set errorMessage(String? value) {
    if (value != null && value != _errorMessage) {
      final summary = value.startsWith('Could not play ')
          ? 'Could not play selected track'
          : value.split(':').first;
      PlaybackDiagnostics.record('Playback error: $summary');
    }
    _errorMessage = value;
  }

  LocalTrack? get currentTrack => queue.isEmpty ? null : queue[currentIndex];

  Future<void> clearTelegramQueue() async {
    if (isLoading) {
      throw StateError('Wait for the current track to finish loading.');
    }
    final current = currentTrack;
    final isTelegram = current?.telegramFileId != null;
    if (isTelegram && isCasting) await stopCasting();
    if (isTelegram && isPlaying) await _backend.pause();
    final local = queue.where((item) => item.telegramFileId == null).toList();
    if (isTelegram) {
      _loadGeneration++;
      _sourceReady = false;
      _wantsPlayback = false;
      isPlaying = false;
      position = Duration.zero;
      duration = Duration.zero;
    }
    queue = List.unmodifiable(local);
    currentIndex = isTelegram || current == null ? 0 : local.indexOf(current);
    if (currentIndex < 0) currentIndex = 0;
    isAllSongsQueue = false;
    _chooseNext();
    notifyListeners();
  }

  Future<void> loadQueue(
    List<LocalTrack> tracks, {
    int initialIndex = 0,
    bool autoplay = true,
    bool allSongs = false,
  }) async {
    if (isCasting) {
      if (tracks.isNotEmpty) {
        await _loadCastTrack(
          tracks,
          initialIndex.clamp(0, tracks.length - 1),
          autoplay: autoplay,
          allSongs: allSongs,
        );
      }
      return;
    }
    if (tracks.isEmpty) return;
    queue = List.unmodifiable(tracks);
    isAllSongsQueue = allSongs;
    currentIndex = initialIndex.clamp(0, tracks.length - 1);
    await _loadCurrent(autoplay: autoplay);
  }

  Future<void> playTrackAt(int index) async {
    if (index < 0 || index >= queue.length) return;
    if (isCasting) {
      await _loadCastTrack(queue, index, autoplay: true);
      return;
    }
    currentIndex = index;
    await _loadCurrent(autoplay: true);
  }

  Future<void> _loadCurrent({required bool autoplay}) async {
    final track = currentTrack;
    if (track == null) return;
    final generation = ++_loadGeneration;
    final telegram = track.telegramFileId != null;
    final preparation = Stopwatch()..start();
    if (telegram) {
      TelegramPlaybackLog.record(
        'Player preparing source (autoplay=$autoplay, local=${!track.path.startsWith('http://127.0.0.1:')})',
      );
    }
    _wantsPlayback = autoplay;
    _pendingSeek = null;
    _chooseNext();
    isLoading = true;
    _startingPlayback = false;
    _sourceReady = false;
    isPlaying = false;
    position = Duration.zero;
    duration = Duration.zero;
    errorMessage = null;
    notifyListeners();
    await _enqueue(() async {
      if (generation != _loadGeneration) return;
      try {
        if (telegram) {
          TelegramPlaybackLog.record(
            'Player source load started after ${preparation.elapsedMilliseconds}ms',
          );
        }
        await _backend.load(track.path);
        if (telegram) {
          TelegramPlaybackLog.record(
            'Player source prepared in ${preparation.elapsedMilliseconds}ms',
          );
        }
        if (generation != _loadGeneration) return;
        await _backend.setVolume(usesSystemVolume ? 1.0 : volume);
        if (generation != _loadGeneration) return;
        isLoading = false;
        _sourceReady = true;
        notifyListeners();
        if (_wantsPlayback) await play();
      } catch (error) {
        if (telegram) {
          TelegramPlaybackLog.record(
            'Player preparation failed type=${error.runtimeType} elapsed=${preparation.elapsedMilliseconds}ms',
          );
        }
        if (generation != _loadGeneration) return;
        isLoading = false;
        PlaybackDiagnostics.record(
          'Track loading failed: ${error.runtimeType}',
        );
        errorMessage = 'Could not play ${track.name}: $error';
        notifyListeners();
      }
    });
  }

  Future<void> play() async {
    if (currentTrack == null) return;
    if (_switchingOutput) return;
    final session = _cast;
    if (session != null) {
      try {
        _castRevision++;
        await session.play();
        isPlaying = true;
        errorMessage = null;
      } catch (error) {
        errorMessage = 'Could not resume casting: $error';
      }
      notifyListeners();
      return;
    }
    _wantsPlayback = true;
    if (isLoading) {
      notifyListeners();
      return;
    }
    if (_startingPlayback) {
      notifyListeners();
      return;
    }
    if (!_sourceReady) {
      await _loadCurrent(autoplay: true);
      return;
    }
    final generation = _loadGeneration;
    _startingPlayback = true;
    notifyListeners();
    try {
      await _backend.play();
      if (generation != _loadGeneration) return;
      if (!_wantsPlayback) {
        await _backend.pause();
        isPlaying = false;
        notifyListeners();
        return;
      }
      if (currentTrack?.telegramFileId != null) {
        TelegramPlaybackLog.record('Player playback started');
      }
      isPlaying = true;
      errorMessage = null;
      notifyListeners();
    } catch (error) {
      if (generation != _loadGeneration) return;
      if (currentTrack?.telegramFileId != null) {
        TelegramPlaybackLog.record(
          'Player play failed type=${error.runtimeType}',
        );
      }
      isPlaying = false;
      errorMessage = 'Could not play ${currentTrack!.name}: $error';
      notifyListeners();
    } finally {
      if (generation == _loadGeneration) {
        _startingPlayback = false;
        notifyListeners();
      }
    }
  }

  Future<void> pause() async {
    _wantsPlayback = false;
    final session = _cast;
    if (session != null) {
      try {
        _castRevision++;
        await session.pause();
        isPlaying = false;
        errorMessage = null;
      } catch (error) {
        errorMessage = 'Could not pause casting: $error';
      }
      notifyListeners();
      return;
    }
    if (isLoading || _startingPlayback) {
      notifyListeners();
      return;
    }
    if (!isPlaying) return;
    try {
      await _backend.pause();
      isPlaying = false;
      notifyListeners();
    } catch (error) {
      errorMessage = 'Could not pause playback: $error';
      notifyListeners();
    }
  }

  Future<void> togglePlayback() => showPauseControl ? pause() : play();

  Future<void> next() async {
    if (queue.isEmpty) return;
    final wasPlaying = showPauseControl;
    if (isCasting) {
      final index = shuffle && queue.length > 1
          ? (_shuffledNext ?? _nextShuffledIndex())
          : (currentIndex + 1) % queue.length;
      await _loadCastTrack(queue, index, autoplay: wasPlaying);
      return;
    }
    if (shuffle && queue.length > 1) {
      currentIndex = _shuffledNext ?? _nextShuffledIndex();
    } else {
      currentIndex = (currentIndex + 1) % queue.length;
    }
    await _loadCurrent(autoplay: wasPlaying);
  }

  Future<void> previous({bool restartCurrent = true}) async {
    if (queue.isEmpty) return;
    if (restartCurrent &&
        previousRestartSeconds > 0 &&
        position > Duration(seconds: previousRestartSeconds)) {
      await seek(Duration.zero);
      return;
    }
    final wasPlaying = showPauseControl;
    if (isCasting) {
      await _loadCastTrack(
        queue,
        (currentIndex - 1 + queue.length) % queue.length,
        autoplay: wasPlaying,
      );
      return;
    }
    currentIndex = (currentIndex - 1 + queue.length) % queue.length;
    await _loadCurrent(autoplay: wasPlaying);
  }

  Duration? _pendingSeek;
  bool _seeking = false;

  Future<void> seek(Duration requested) async {
    if (currentTrack == null) return;
    final target = requested < Duration.zero
        ? Duration.zero
        : duration > Duration.zero && requested > duration
        ? duration
        : requested;
    final cast = _cast;
    if (cast != null) {
      try {
        _castRevision++;
        await cast.seek(target);
        if (identical(_cast, cast)) {
          position = target;
          notifyListeners();
        }
      } catch (error) {
        errorMessage = 'Could not seek in this track: $error';
        notifyListeners();
      }
      return;
    }
    if (isCasting) return;
    _pendingSeek = target;
    position = target;
    notifyListeners();
    if (_seeking) return;
    _seeking = true;
    try {
      while (_pendingSeek != null) {
        final next = _pendingSeek!;
        _pendingSeek = null;
        final generation = _loadGeneration;
        await _enqueue(() async {
          if (generation == _loadGeneration && !isLoading) {
            await _backend.seek(next);
            if (generation == _loadGeneration && _pendingSeek == null) {
              position = next;
              notifyListeners();
            }
          }
        });
      }
    } catch (error) {
      _pendingSeek = null;
      errorMessage = 'Could not seek in this track: $error';
      notifyListeners();
    } finally {
      _seeking = false;
    }
  }

  Future<void> setVolume(double requested) async {
    final cast = _cast;
    if (cast != null) {
      if (!cast.supportsVolume) return;
      final value = requested.clamp(0.0, 1.0);
      _castRevision++;
      try {
        await cast.setVolume(value);
        if (identical(_cast, cast) && !_disposed) {
          volume = value;
          errorMessage = null;
          notifyListeners();
        }
      } catch (error) {
        if (!_disposed && identical(_cast, cast)) {
          errorMessage = 'Could not adjust receiver volume: $error';
          notifyListeners();
        }
      }
      return;
    }
    if (isCasting) return;
    volume = requested.clamp(0, 1).toDouble();
    final revision = ++_volumeRevision;
    notifyListeners();
    try {
      final system = _systemVolume;
      if (system != null) {
        _volumeWrites++;
        try {
          final actual = await system.set(volume);
          if (!_disposed && revision == _volumeRevision) {
            volume = actual.clamp(0.0, 1.0);
            notifyListeners();
          }
        } finally {
          _volumeWrites--;
        }
      } else {
        await _backend.setVolume(volume);
      }
    } catch (error) {
      if (!_disposed) {
        errorMessage = 'Could not change playback volume: $error';
        notifyListeners();
      }
    }
  }

  void setRepeat(bool value) {
    repeat = value;
    notifyListeners();
  }

  void setShuffle(bool value) {
    shuffle = value;
    _chooseNext();
    notifyListeners();
  }

  int _nextShuffledIndex() {
    if (queue.length < 2) return currentIndex;
    var nextIndex = currentIndex;
    while (nextIndex == currentIndex) {
      nextIndex = _random.nextInt(queue.length);
    }
    return nextIndex;
  }

  void _onPlayerState(PlayerState state) {
    if (isCasting) return;
    if (isLoading) return;
    if (state == PlayerState.playing && !_wantsPlayback) return;
    isPlaying = state == PlayerState.playing;
    if (state == PlayerState.completed) position = duration;
    notifyListeners();
  }

  void _onBackendError(Object error, StackTrace stackTrace) {
    if (_disposed || isCasting) return;
    // All of audioplayers' filtered event streams can emit the same error.
    if (!_sourceReady && !isLoading && errorMessage != null) return;
    PlaybackDiagnostics.record('Audio backend error: ${error.runtimeType}');
    _loadGeneration++;
    _sourceReady = false;
    _wantsPlayback = false;
    _startingPlayback = false;
    isLoading = false;
    isPlaying = false;
    errorMessage = 'Playback was interrupted. Tap play to try again.';
    if (currentTrack?.telegramFileId != null) {
      TelegramPlaybackLog.record(
        'Player event failed type=${error.runtimeType}',
      );
    }
    notifyListeners();
  }

  Future<void> _handleCompletion() async {
    if (isCasting || queue.isEmpty) return;
    if (repeat || queue.length > 1) {
      if (repeat && !shuffle) {
        await seek(Duration.zero);
        await play();
      } else {
        currentIndex = shuffle
            ? (_shuffledNext ?? _nextShuffledIndex())
            : (currentIndex + 1) % queue.length;
        await _loadCurrent(autoplay: true);
      }
    } else {
      _wantsPlayback = false;
      isPlaying = false;
      position = duration;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final session = _cast;
    if (session != null) unawaited(session.close());
    _volumeTimer?.cancel();
    _castTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_backend.dispose());
    super.dispose();
  }
}
