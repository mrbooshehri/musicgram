import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/cast_media_server.dart';

void main() {
  test(
    'relays Telegram stream ranges without exposing the source URL',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((request) async {
        if (request.method == 'HEAD') {
          request.response.contentLength = 100;
        } else {
          expect(request.headers.value('range'), 'bytes=10-19');
          request.response.statusCode = 206;
          request.response.contentLength = 10;
          request.response.add(List.generate(10, (i) => i + 10));
        }
        await request.response.close();
      });
      final source = Uri.parse('http://127.0.0.1:${upstream.port}/private');
      final server = await CastMediaServer.startStream(
        source,
        'Telegram track',
        InternetAddress.loopbackIPv4,
        mimeType: 'audio/mpeg',
      );
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.close();
        await upstream.close(force: true);
      });
      expect(server.uri.path, isNot(contains('private')));
      final request = await client.getUrl(server.uri);
      request.headers.set('Range', 'bytes=10-19');
      final response = await request.close();
      expect(response.statusCode, 206);
      expect(response.headers.contentType?.mimeType, 'audio/mpeg');
      expect(
        await response.expand((chunk) => chunk).toList(),
        List.generate(10, (i) => i + 10),
      );
      await expectLater(
        CastMediaServer.startStream(
          Uri.parse('http://example.com/song'),
          'song.mp3',
          InternetAddress.loopbackIPv4,
        ),
        throwsArgumentError,
      );
    },
  );
  test('detects an extensionless local MP3 from its header', () async {
    final dir = await Directory.systemTemp.createTemp('cast_audio');
    final file = File('${dir.path}/audio');
    await file.writeAsBytes([0x49, 0x44, 0x33, 0, 0]);
    final server = await CastMediaServer.start(
      file,
      InternetAddress.loopbackIPv4,
    );
    addTearDown(() async {
      await server.close();
      await dir.delete(recursive: true);
    });
    expect(server.contentType.mimeType, 'audio/mpeg');
  });
  test('detects an extensionless Telegram stream from its header', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      if (request.method == 'HEAD') {
        request.response.contentLength = 8;
      } else {
        expect(request.headers.value('range'), 'bytes=0-7');
        request.response.statusCode = 206;
        request.response.contentLength = 8;
        request.response.add([0x49, 0x44, 0x33, 0, 0, 0, 0, 0]);
      }
      await request.response.close();
    });
    final server = await CastMediaServer.startStream(
      Uri.parse('http://127.0.0.1:${upstream.port}/token'),
      'Telegram track',
      InternetAddress.loopbackIPv4,
    );
    addTearDown(() async {
      await server.close();
      await upstream.close(force: true);
    });
    expect(server.contentType.mimeType, 'audio/mpeg');
  });
  test('serves only selected audio with HEAD and byte-range support', () async {
    final dir = await Directory.systemTemp.createTemp('musicgram_cast_test');
    final file = File('${dir.path}/track.mp3');
    await file.writeAsBytes(List.generate(100, (i) => i));
    final server = await CastMediaServer.start(
      file,
      InternetAddress.loopbackIPv4,
    );
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.close();
      await dir.delete(recursive: true);
    });
    final uri = server.uri;
    expect(uri.path, isNot(contains('track.mp3')));
    final head = await (await client.openUrl('HEAD', uri)).close();
    expect(head.statusCode, 200);
    expect(head.contentLength, 100);
    expect(head.headers.contentType?.mimeType, 'audio/mpeg');
    await head.drain<void>();
    final req = await client.getUrl(uri);
    req.headers.set('Range', 'bytes=10-19');
    final response = await req.close();
    expect(response.statusCode, 206);
    expect(response.headers.value('Content-Range'), 'bytes 10-19/100');
    expect(
      await response.expand((item) => item).toList(),
      List.generate(10, (i) => i + 10),
    );
    final bad = await (await client.getUrl(uri.replace(path: '/other')))
        .close();
    expect(bad.statusCode, 404);
    await bad.drain<void>();
    final invalid = await client.getUrl(uri);
    invalid.headers.set('Range', 'bytes=101-');
    final rejected = await invalid.close();
    expect(rejected.statusCode, 416);
    await rejected.drain<void>();
  });
}
