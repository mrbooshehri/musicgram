import 'dart:io';
import 'dart:math';

/// Serves a single, explicitly selected file at an unguessable temporary URL.
class CastMediaServer {
  CastMediaServer._(
    this._server,
    this._file,
    this._length,
    this._token,
    this.contentType, {
    this._upstream,
    this._client,
  }) {
    _server.listen(_serve);
  }
  final HttpServer _server;
  final File? _file;
  final Uri? _upstream;
  final HttpClient? _client;
  final int _length;
  final String _token;
  final ContentType contentType;

  static Future<CastMediaServer> start(
    File file,
    InternetAddress address, {
    String? mimeType,
  }) async {
    final length = await file.length();
    if (length <= 0) throw StateError('The selected audio file is empty.');
    ContentType mime;
    try {
      mime = _mimeType(file.path, mimeType);
    } on UnsupportedError {
      final handle = await file.open();
      try {
        mime = _sniff(await handle.read(16));
      } finally {
        await handle.close();
      }
    }
    final token = _newToken();
    final server = await HttpServer.bind(address, 0, shared: false);
    return CastMediaServer._(server, file, length, token, mime);
  }

  static ContentType _mimeType(String name, [String? supplied]) {
    final normalized = supplied?.split(';').first.trim().toLowerCase();
    if (normalized != null && normalized.startsWith('audio/')) {
      return ContentType.parse(normalized);
    }
    final extension = name.toLowerCase().split('.').last;
    final mime = switch (extension) {
      'mp3' => 'audio/mpeg',
      'm4a' || 'mp4' => 'audio/mp4',
      'aac' => 'audio/aac',
      'flac' => 'audio/flac',
      'wav' => 'audio/wav',
      'ogg' || 'opus' => 'audio/ogg',
      _ => throw UnsupportedError(
        'This audio format is not supported for casting.',
      ),
    };
    return ContentType.parse(mime);
  }

  static ContentType _sniff(List<int> bytes) {
    bool starts(List<int> signature) =>
        bytes.length >= signature.length &&
        List.generate(
          signature.length,
          (i) => bytes[i] == signature[i],
        ).every((x) => x);
    if (starts([0x49, 0x44, 0x33]) ||
        (bytes.length >= 2 &&
            bytes[0] == 0xff &&
            (bytes[1] & 0xe0) == 0xe0 &&
            (bytes[1] & 0x06) != 0)) {
      return ContentType.parse('audio/mpeg');
    }
    if (starts([0xff, 0xf1]) || starts([0xff, 0xf9])) {
      return ContentType.parse('audio/aac');
    }
    if (starts([0x66, 0x4c, 0x61, 0x43])) {
      return ContentType.parse('audio/flac');
    }
    if (starts([0x4f, 0x67, 0x67, 0x53])) return ContentType.parse('audio/ogg');
    if (starts([0x52, 0x49, 0x46, 0x46]) &&
        bytes.length >= 12 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x41 &&
        bytes[10] == 0x56 &&
        bytes[11] == 0x45) {
      return ContentType.parse('audio/wav');
    }
    if (bytes.length >= 8 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      return ContentType.parse('audio/mp4');
    }
    throw UnsupportedError('This audio format is not supported for casting.');
  }

  static String _newToken() => List.generate(
    24,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  /// Relays only the already-registered local Telegram stream.
  static Future<CastMediaServer> startStream(
    Uri source,
    String name,
    InternetAddress address, {
    String? mimeType,
  }) async {
    if (source.scheme != 'http' ||
        source.host != '127.0.0.1' ||
        !source.hasPort ||
        source.userInfo.isNotEmpty) {
      throw ArgumentError('Invalid Telegram stream address');
    }
    final client = HttpClient();
    try {
      final request = await client.openUrl('HEAD', source);
      request.followRedirects = false;
      final response = await request.close();
      final length = response.contentLength;
      await response.drain<void>();
      if (response.statusCode != 200 || length <= 0) {
        throw StateError('Telegram audio is unavailable.');
      }
      ContentType type;
      try {
        type = _mimeType(name, mimeType);
      } on UnsupportedError {
        final probe = await client.getUrl(source);
        probe.followRedirects = false;
        probe.headers.set(
          HttpHeaders.rangeHeader,
          'bytes=0-${min(15, length - 1)}',
        );
        final probeResponse = await probe.close();
        if (probeResponse.statusCode != HttpStatus.partialContent) {
          await probeResponse.drain<void>();
          throw StateError('Could not identify Telegram audio format.');
        }
        type = _sniff(await probeResponse.expand((bytes) => bytes).toList());
      }
      final server = await HttpServer.bind(address, 0, shared: false);
      return CastMediaServer._(
        server,
        null,
        length,
        _newToken(),
        type,
        upstream: source,
        client: client,
      );
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
  }

  Uri get uri => Uri(
    scheme: 'http',
    host: _server.address.address,
    port: _server.port,
    path: '/$_token',
  );

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    if (request.uri.path != '/$_token') {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    if (request.method != 'GET' && request.method != 'HEAD') {
      response.statusCode = HttpStatus.methodNotAllowed;
      response.headers.set('Allow', 'GET, HEAD');
      await response.close();
      return;
    }
    var start = 0;
    var end = _length - 1;
    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (range != null) {
      final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range);
      if (match == null || (match[1]!.isEmpty && match[2]!.isEmpty)) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes */$_length',
        );
        await response.close();
        return;
      }
      if (match[1]!.isEmpty) {
        final suffix = int.tryParse(match[2]!) ?? 0;
        start = suffix <= 0 ? _length : max(0, _length - suffix);
      } else {
        start = int.tryParse(match[1]!) ?? _length;
        if (match[2]!.isNotEmpty) end = min(end, int.tryParse(match[2]!) ?? -1);
      }
      if (start >= _length || end < start) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes */$_length',
        );
        await response.close();
        return;
      }
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$_length',
      );
    }
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    if (request.headers.value('getcontentFeatures.dlna.org') == '1') {
      response.headers.set(
        'contentFeatures.dlna.org',
        'DLNA.ORG_OP=01;DLNA.ORG_CI=0',
      );
    }
    response.headers.set('transferMode.dlna.org', 'Streaming');
    response.headers.contentType = contentType;
    response.contentLength = end - start + 1;
    try {
      if (request.method == 'GET') {
        if (_upstream != null) {
          final upstreamRequest = await _client!.getUrl(_upstream);
          upstreamRequest.followRedirects = false;
          upstreamRequest.headers.set(
            HttpHeaders.rangeHeader,
            'bytes=$start-$end',
          );
          final upstreamResponse = await upstreamRequest.close();
          if (upstreamResponse.statusCode != HttpStatus.partialContent ||
              upstreamResponse.contentLength != end - start + 1) {
            throw StateError('Telegram stream range is unavailable.');
          }
          await response.addStream(upstreamResponse);
        } else {
          await response.addStream(_file!.openRead(start, end + 1));
        }
      }
      await response.close();
    } catch (_) {
      await response.close().catchError((_) {});
    }
  }

  Future<void> close() async {
    _client?.close(force: true);
    await _server.close(force: true);
  }
}
