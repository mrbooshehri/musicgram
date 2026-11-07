import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class LyricsRecord {
  const LyricsRecord({
    required this.id,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    required this.duration,
    required this.instrumental,
    this.plainLyrics,
    this.syncedLyrics,
  });

  factory LyricsRecord.fromJson(Map<String, dynamic> json) => LyricsRecord(
    id: (json['id'] as num?)?.toInt() ?? 0,
    trackName: json['trackName'] as String? ?? '',
    artistName: json['artistName'] as String? ?? '',
    albumName: json['albumName'] as String? ?? '',
    duration: (json['duration'] as num?)?.toDouble() ?? 0,
    instrumental: json['instrumental'] == true,
    plainLyrics: json['plainLyrics'] as String?,
    syncedLyrics: json['syncedLyrics'] as String?,
  );

  final int id;
  final String trackName;
  final String artistName;
  final String albumName;
  final double duration;
  final bool instrumental;
  final String? plainLyrics;
  final String? syncedLyrics;

  Map<String, dynamic> toJson() => {
    'id': id,
    'trackName': trackName,
    'artistName': artistName,
    'albumName': albumName,
    'duration': duration,
    'instrumental': instrumental,
    'plainLyrics': plainLyrics,
    'syncedLyrics': syncedLyrics,
  };
}

class LyricLine {
  const LyricLine(this.time, this.text);
  final Duration time;
  final String text;
}

List<LyricLine> parseSyncedLyrics(String input) {
  final stamp = RegExp(r'\[(\d+):(\d{2})(?:\.(\d{1,3}))?\]');
  final lines = <LyricLine>[];
  for (final line in const LineSplitter().convert(input)) {
    final matches = stamp.allMatches(line).toList();
    if (matches.isEmpty) continue;
    final text = line.replaceAll(stamp, '').trim();
    for (final match in matches) {
      final fraction = (match[3] ?? '').padRight(3, '0');
      final millis =
          int.parse(match[1]!) * 60000 +
          int.parse(match[2]!) * 1000 +
          int.parse(fraction);
      lines.add(LyricLine(Duration(milliseconds: millis), text));
    }
  }
  lines.sort((a, b) => a.time.compareTo(b.time));
  return lines;
}

int activeLyricIndex(List<LyricLine> lines, Duration position) {
  var low = 0;
  var high = lines.length;
  while (low < high) {
    final mid = (low + high) ~/ 2;
    if (lines[mid].time <= position) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low - 1;
}

class LyricsService {
  LyricsService({Uri? endpoint})
    : endpoint = endpoint ?? Uri.https('lrclib.net', '/api/search');
  final Uri endpoint;

  Future<List<LyricsRecord>> search({
    String? query,
    String? title,
    String? artist,
  }) async {
    final params = <String, String>{};
    if (query != null && query.trim().isNotEmpty) {
      params['q'] = query.trim();
    } else {
      if (title == null || title.trim().isEmpty) return [];
      params['track_name'] = title.trim();
      if (artist != null &&
          artist.trim().isNotEmpty &&
          artist != 'Unknown artist') {
        params['artist_name'] = artist.trim();
      }
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client
          .getUrl(endpoint.replace(queryParameters: params))
          .timeout(const Duration(seconds: 15));
      request.headers.set(
        'Lrclib-Client',
        'MusicGram/0.1.0 (https://github.com/mrbooshehri/red-flutter)',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200) {
        throw HttpException('LRCLIB returned ${response.statusCode}');
      }
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(body);
      if (decoded is! List) {
        throw const FormatException('Invalid LRCLIB response');
      }
      return decoded
          .whereType<Map>()
          .map((item) => LyricsRecord.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } finally {
      client.close(force: true);
    }
  }
}

class LyricsCache {
  LyricsCache({this.directory});
  final Future<Directory> Function()? directory;
  Future<void> _writes = Future.value();

  Future<File> _file() async {
    final dir = await (directory?.call() ?? getApplicationSupportDirectory());
    return File('${dir.path}/selected_lyrics.json');
  }

  Future<Map<String, dynamic>> _read() async {
    try {
      final data = jsonDecode(await (await _file()).readAsString());
      return data is Map ? Map<String, dynamic>.from(data) : {};
    } on FileSystemException {
      return {};
    } on FormatException {
      return {};
    }
  }

  Future<LyricsRecord?> load(String key) async {
    await _writes;
    final value = (await _read())[key];
    if (value is! Map) return null;
    try {
      return LyricsRecord.fromJson(Map<String, dynamic>.from(value));
    } on TypeError {
      return null;
    }
  }

  Future<void> save(String key, LyricsRecord record) {
    final write = _writes.then((_) async {
      final data = await _read();
      data[key] = record.toJson();
      final file = await _file();
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(data), flush: true);
      await temp.rename(file.path);
    });
    _writes = write.catchError((_) {});
    return write;
  }
}
