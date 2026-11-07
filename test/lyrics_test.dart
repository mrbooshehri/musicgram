import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/lyrics.dart';

void main() {
  test('LRC timestamps, repeated timestamps and unsorted lines are parsed', () {
    final lines = parseSyncedLyrics(
      '[00:02.50][00:04.00]Second\n[00:01.2]First\n[ar:Artist]',
    );
    expect(lines.map((line) => line.text), ['First', 'Second', 'Second']);
    expect(lines.map((line) => line.time.inMilliseconds), [1200, 2500, 4000]);
    expect(activeLyricIndex(lines, const Duration(milliseconds: 2499)), 0);
    expect(activeLyricIndex(lines, Duration.zero), -1);
  });

  test('selected lyrics persist by track and are readable offline', () async {
    final directory = await Directory.systemTemp.createTemp();
    addTearDown(() => directory.delete(recursive: true));
    final store = LyricsCache(directory: () async => directory);
    final record = LyricsRecord.fromJson({
      'id': 1,
      'trackName': 'Title',
      'artistName': 'Artist',
      'syncedLyrics': '[00:01.00]Hello',
      'plainLyrics': 'Hello',
    });
    await store.save('track-a', record);
    expect(
      (await LyricsCache(directory: () async => directory).load('track-a'))
          ?.syncedLyrics,
      '[00:01.00]Hello',
    );
    expect(await store.load('track-b'), isNull);
  });

  test('search encodes keywords and handles LRCLIB results', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      expect(request.uri.queryParameters['q'], 'Beyoncé & more');
      expect(request.headers.value('Lrclib-Client'), contains('MusicGram'));
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode([
          {
            'id': 2,
            'trackName': 'Song',
            'artistName': 'Artist',
            'plainLyrics': 'words',
          },
        ]),
      );
      await request.response.close();
    });
    final service = LyricsService(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/api/search'),
    );
    final results = await service.search(query: 'Beyoncé & more');
    expect(results.single.trackName, 'Song');
    expect(results.single.plainLyrics, 'words');
  });
}
