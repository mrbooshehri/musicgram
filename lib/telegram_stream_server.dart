import 'dart:io';
import 'dart:math';
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'telegram_music_library.dart';
import 'telegram_playback_log.dart';
import 'playback_controller.dart';
import 'telegram_errors.dart';

class _StreamFile {
  _StreamFile(
    this.originalId,
    this.size,
    this.remoteId,
    this.chatId,
    this.messageId,
  );
  final int originalId;
  final int size;
  final String? remoteId;
  final int? chatId;
  final int? messageId;
  Future<int>? resolved;
  int contiguousBytes = 0;
  TdlibRequestException? terminalError;
  DateTime? terminalUntil;

  TdlibRequestException? get blockedError {
    final until = terminalUntil;
    if (until != null && DateTime.now().isBefore(until)) return terminalError;
    terminalError = null;
    terminalUntil = null;
    return null;
  }
}

/// Serves TDLib file ranges to an audio player on the loopback interface.
class TelegramStreamServer {
  TelegramStreamServer(
    this.request, {
    this.prebufferDelay = const Duration(seconds: 2),
  });
  final TelegramRequest request;
  final ValueNotifier<int> bufferRevision = ValueNotifier(0);

  double bufferedFraction(String? url) {
    final file = _registeredFile(url);
    if (file == null || file.size <= 0) return 0;
    return (file.contiguousBytes / file.size).clamp(0.0, 1.0);
  }

  void _recordBuffered(_StreamFile file, int offset, int length) {
    if (offset > file.contiguousBytes) return;
    final end = min(file.size, offset + length);
    if (end > file.contiguousBytes) {
      file.contiguousBytes = end;
      if (!_closed) bufferRevision.value++;
    }
  }

  final Duration prebufferDelay;
  HttpServer? _server;
  Future<HttpServer>? _starting;
  final Map<String, _StreamFile> _files = {};
  int _nextFile = 0;
  Future<void> _pending = Future.value();
  int _requestNumber = 0;
  final Map<_StreamFile, int> _activeStreams = {};
  _StreamFile? _wantedPrebuffer;
  _StreamFile? _lastPrebuffer;
  Timer? _prebufferTimer;
  bool _prebufferRunning = false;
  bool _closed = false;
  final String _token = List.generate(
    24,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  _StreamFile? _registeredFile(String? url) {
    if (url == null || _server == null) return null;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'http' ||
        uri.host != '127.0.0.1' ||
        uri.port != _server!.port ||
        uri.pathSegments.length != 2 ||
        uri.pathSegments.first != _token) {
      return null;
    }
    return _files[uri.pathSegments.last];
  }

  bool _sameFile(_StreamFile a, _StreamFile b) =>
      identical(a, b) ||
      (a.remoteId != null &&
          a.remoteId!.isNotEmpty &&
          a.remoteId == b.remoteId) ||
      (a.chatId != null &&
          a.messageId != null &&
          a.chatId == b.chatId &&
          a.messageId == b.messageId) ||
      a.originalId == b.originalId;

  /// Warms only the predicted next streamed file, without delaying playback.
  void updatePrebuffer(PlaybackController player) {
    final nextIndex = player.nextIndex;
    final next =
        player.isPlaying &&
            nextIndex != null &&
            !(player.repeat && !player.shuffle)
        ? _registeredFile(player.queue[nextIndex].path)
        : null;
    final current = _registeredFile(player.currentTrack?.path);
    final candidate =
        next != null && (current == null || !_sameFile(current, next))
        ? next
        : null;
    if (identical(candidate, _wantedPrebuffer)) return;
    _wantedPrebuffer = candidate;
    _prebufferTimer?.cancel();
    if (candidate != null && !_closed) {
      _prebufferTimer = Timer(prebufferDelay, _startPrebuffer);
    }
  }

  Future<void> _startPrebuffer() async {
    final file = _wantedPrebuffer;
    if (_closed ||
        file == null ||
        _prebufferRunning ||
        identical(file, _lastPrebuffer)) {
      return;
    }
    if (_activeStreams.keys.any((active) => _sameFile(active, file))) return;
    _prebufferRunning = true;
    try {
      final id = await _resolveFile(file);
      if (_closed ||
          !identical(file, _wantedPrebuffer) ||
          _activeStreams.keys.any((active) => _sameFile(active, file))) {
        return;
      }
      _lastPrebuffer = file;
      await request({
        '@type': 'downloadFile',
        'file_id': id,
        'priority': 1,
        'offset': 0,
        'limit': min(file.size, 256 * 1024),
        'synchronous': true,
      });
      TelegramPlaybackLog.record('Next track prebuffer completed');
    } catch (error) {
      if (identical(_lastPrebuffer, file)) _lastPrebuffer = null;
      TelegramPlaybackLog.record(
        'Next track prebuffer ended type=${error.runtimeType}',
      );
    } finally {
      _prebufferRunning = false;
      if (!_closed &&
          _wantedPrebuffer != null &&
          !identical(_wantedPrebuffer, file)) {
        _prebufferTimer?.cancel();
        _prebufferTimer = Timer(prebufferDelay, _startPrebuffer);
      }
    }
  }

  Future<String> register(
    int fileId,
    int size, {
    String? remoteId,
    int? chatId,
    int? messageId,
  }) async {
    if (size <= 0) throw ArgumentError('Audio file size is not available');
    final server = _server ??= await (_starting ??= HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    ));
    if (_files.isEmpty) {
      server.listen(_serve);
      TelegramPlaybackLog.record('Stream server started on loopback');
    }
    final key = '${_nextFile++}';
    _files[key] = _StreamFile(fileId, size, remoteId, chatId, messageId);
    return 'http://127.0.0.1:${server.port}/$_token/$key';
  }

  Future<int> _resolveFile(_StreamFile file) async {
    final existing = file.resolved;
    if (existing != null) return existing;
    final resolution = _findCurrentFileId(file);
    file.resolved = resolution;
    try {
      return await resolution;
    } catch (_) {
      file.resolved = null;
      rethrow;
    }
  }

  Future<int> _findCurrentFileId(_StreamFile file) async {
    final remoteId = file.remoteId;
    if (remoteId != null &&
        remoteId.isNotEmpty &&
        !remoteId.startsWith('http://') &&
        !remoteId.startsWith('https://')) {
      try {
        final result = await request({
          '@type': 'getRemoteFile',
          'remote_file_id': remoteId,
          'file_type': null,
        });
        if (result['id'] is int && (result['id'] as int) > 0) {
          TelegramPlaybackLog.record(
            'Resolved current file from persistent remote identifier',
          );
          return result['id'] as int;
        }
      } catch (error) {
        TelegramPlaybackLog.record(
          'Remote file resolution failed type=${error.runtimeType}',
        );
      }
    }
    final messageFile = await _messageFileId(file);
    if (messageFile != null) return messageFile;
    TelegramPlaybackLog.record(
      'Using existing file identifier; stable resolution unavailable',
    );
    return file.originalId;
  }

  Future<int?> _messageFileId(_StreamFile file) async {
    if (file.chatId != null && file.messageId != null) {
      try {
        final message = await request({
          '@type': 'getMessage',
          'chat_id': file.chatId,
          'message_id': file.messageId,
        });
        final content = message['content'];
        final media = content is Map
            ? content['audio'] ?? content['document']
            : null;
        final value = media is Map ? media['audio'] ?? media['document'] : null;
        if (value is Map && value['id'] is int && (value['id'] as int) > 0) {
          TelegramPlaybackLog.record(
            'Resolved current file from Telegram message',
          );
          return value['id'] as int;
        }
      } catch (error) {
        TelegramPlaybackLog.record(
          'Message file resolution failed type=${error.runtimeType}',
        );
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> _downloadRange(
    _StreamFile file,
    int offset,
    int length,
  ) async {
    var id = await _resolveFile(file);
    Future<Map<String, dynamic>> download() => request({
      '@type': 'downloadFile',
      'file_id': id,
      'priority': 32,
      'offset': offset,
      'limit': length,
      'synchronous': true,
    });
    try {
      return await download();
    } on TdlibRequestException catch (error) {
      if (error.code != 400) rethrow;
      final refreshed = await _messageFileId(file);
      if (refreshed == null) rethrow;
      id = refreshed;
      file.resolved = Future.value(id);
      TelegramPlaybackLog.record(
        'Retrying audio range with refreshed message file',
      );
      return await download();
    }
  }

  /// Reads a range only when TDLib confirms those exact bytes are available.
  Future<List<int>?> _readCachedRange(
    _StreamFile file,
    int offset,
    int length,
  ) async {
    try {
      final id = await _resolveFile(file);
      final prefix = await request({
        '@type': 'getFileDownloadedPrefixSize',
        'file_id': id,
        'offset': offset,
      });
      if (prefix['size'] is! int || (prefix['size'] as int) < length) {
        return null;
      }
      final state = await request({'@type': 'getFile', 'file_id': id});
      final local = state['local'];
      if (local is! Map ||
          local['path'] is! String ||
          (local['path'] as String).isEmpty) {
        return null;
      }
      final handle = await File(local['path'] as String).open();
      try {
        await handle.setPosition(offset);
        final bytes = await handle.read(length);
        return bytes.length == length ? bytes : null;
      } finally {
        await handle.close();
      }
    } catch (_) {
      // A stale or evicted TDLib file is downloaded through the normal path.
      return null;
    }
  }

  Future<void> _serve(HttpRequest http) async {
    final parts = http.uri.pathSegments;
    final file = parts.length == 2 && parts.first == _token
        ? _files[parts.last]
        : null;
    if (file == null || (http.method != 'GET' && http.method != 'HEAD')) {
      http.response.statusCode = HttpStatus.notFound;
      await http.response.close();
      return;
    }
    final requestNumber = ++_requestNumber;
    final size = file.size;
    var start = 0;
    var end = size - 1;
    final header = http.headers.value(HttpHeaders.rangeHeader);
    if (header != null) {
      final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header);
      if (match == null || (match[1]!.isEmpty && match[2]!.isEmpty)) {
        http.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        await http.response.close();
        return;
      }
      if (match[1]!.isEmpty) {
        final suffix = int.parse(match[2]!);
        start = max(0, size - suffix);
      } else {
        start = int.parse(match[1]!);
        if (match[2]!.isNotEmpty) end = min(end, int.parse(match[2]!));
      }
      if (start >= size || end < start) {
        http.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        http.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes */$size',
        );
        await http.response.close();
        return;
      }
      http.response.statusCode = HttpStatus.partialContent;
      http.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$size',
      );
    }
    if (file.blockedError != null &&
        await _readCachedRange(file, start, min(32 * 1024, end - start + 1)) ==
            null) {
      http.response.statusCode = HttpStatus.notFound;
      await http.response.close();
      return;
    }
    TelegramPlaybackLog.record(
      'HTTP #$requestNumber ${http.method} range=$start-$end size=$size status=${http.response.statusCode}',
    );
    http.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    http.response.headers.contentType = ContentType.binary;
    http.response.contentLength = end - start + 1;
    if (http.method == 'HEAD') {
      await http.response.close();
      return;
    }
    _activeStreams[file] = (_activeStreams[file] ?? 0) + 1;
    var startedSending = false;
    try {
      for (var pos = start; pos <= end;) {
        // Send the first bytes promptly so the player can identify the audio
        // without waiting for a large range over a slow connection.
        final chunkSize = pos == start ? 32 * 1024 : 128 * 1024;
        final length = min(chunkSize, end - pos + 1);
        final offset = pos;
        final done = Completer<List<int>>();
        final queuedAt = Stopwatch()..start();
        _pending = _pending.catchError((_) {}).then((_) async {
          final elapsed = Stopwatch()..start();
          final logRange =
              offset == start || (offset - start) % (1024 * 1024) == 0;
          if (logRange) {
            TelegramPlaybackLog.record(
              'HTTP #$requestNumber TDLib range offset=$offset bytes=$length queued=${queuedAt.elapsedMilliseconds}ms',
            );
          }
          try {
            final cached = await _readCachedRange(file, offset, length);
            if (cached != null) {
              if (logRange) {
                TelegramPlaybackLog.record(
                  'HTTP #$requestNumber cached range bytes=${cached.length}',
                );
              }
              _recordBuffered(file, offset, cached.length);
              done.complete(cached);
              return;
            }
            final blocked = file.blockedError;
            if (blocked != null) throw blocked;
            final result = await _downloadRange(file, offset, length);
            final id = await _resolveFile(file);
            final local = result['local'];
            if (local is! Map ||
                local['path'] is! String ||
                (local['path'] as String).isEmpty) {
              TelegramPlaybackLog.record(
                'HTTP #$requestNumber TDLib returned no local file',
              );
              throw StateError('Audio range unavailable');
            }
            final prefix = await request({
              '@type': 'getFileDownloadedPrefixSize',
              'file_id': id,
              'offset': offset,
            });
            if (prefix['size'] is! int || (prefix['size'] as int) < length) {
              TelegramPlaybackLog.record(
                'HTTP #$requestNumber prefix incomplete: available=${prefix['size'] is int ? prefix['size'] : 'unknown'} expected=$length',
              );
              throw StateError('Audio range was not fully downloaded');
            }
            final handle = await File(local['path'] as String).open();
            try {
              await handle.setPosition(offset);
              final bytes = await handle.read(length);
              if (bytes.length != length) {
                throw StateError('Incomplete audio range');
              }
              if (logRange) {
                TelegramPlaybackLog.record(
                  'HTTP #$requestNumber range ready bytes=${bytes.length} elapsed=${elapsed.elapsedMilliseconds}ms',
                );
              }
              _recordBuffered(file, offset, bytes.length);
              done.complete(bytes);
            } finally {
              await handle.close();
            }
          } catch (e, s) {
            if (e is TdlibRequestException && e.code == 400) {
              file.terminalError = e;
              file.terminalUntil = DateTime.now().add(
                const Duration(seconds: 15),
              );
            }
            TelegramPlaybackLog.record(
              'HTTP #$requestNumber range failed type=${e.runtimeType} elapsed=${elapsed.elapsedMilliseconds}ms',
            );
            done.completeError(e, s);
          }
        });
        final data = await done.future;
        startedSending = true;
        http.response.add(data);
        await http.response.flush();
        if (pos == start) {
          TelegramPlaybackLog.record(
            'HTTP #$requestNumber first audio bytes sent',
          );
        }
        pos += length;
      }
      await http.response.close();
    } catch (error) {
      TelegramPlaybackLog.record(
        'HTTP #$requestNumber stream ended type=${error.runtimeType}',
      );
      if (!startedSending) {
        http.response.statusCode =
            error is TdlibRequestException && error.code == 400
            ? HttpStatus.notFound
            : HttpStatus.badGateway;
        http.response.contentLength = 0;
        http.response.headers.removeAll(HttpHeaders.contentRangeHeader);
      }
      await http.response.close().catchError((_) {});
    } finally {
      final remaining = (_activeStreams[file] ?? 1) - 1;
      if (remaining == 0) {
        _activeStreams.remove(file);
      } else {
        _activeStreams[file] = remaining;
      }
    }
  }

  Future<void> close() async {
    _closed = true;
    _wantedPrebuffer = null;
    _prebufferTimer?.cancel();
    await _server?.close(force: true);
    _server = null;
    _starting = null;
    _files.clear();
  }
}
