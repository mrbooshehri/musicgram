import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/telegram_stream_server.dart';
import 'package:musicgram/telegram_playback_log.dart';
import 'package:musicgram/playback_controller.dart';
import 'package:musicgram/telegram_errors.dart';

import 'fake_audio_backend.dart';

void main() {
  test(
    'replay and a full download reuse verified TDLib cached bytes',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'telegram_shared_cache',
      );
      final file = File('${dir.path}/audio');
      final bytes = List.generate(64, (i) => i);
      var available = false;
      var downloads = 0;
      Future<Map<String, dynamic>> request(Map<String, Object?> query) async {
        switch (query['@type']) {
          case 'getFileDownloadedPrefixSize':
            final offset = query['offset'] as int;
            return {'size': available ? bytes.length - offset : 0};
          case 'getFile':
            return {
              'local': {'path': file.path},
            };
          case 'downloadFile':
            downloads++;
            await file.writeAsBytes(bytes);
            available = true;
            return {
              'local': {'path': file.path},
            };
        }
        throw StateError('unexpected request');
      }

      final client = HttpClient();
      var server = TelegramStreamServer(request);
      addTearDown(() async {
        client.close(force: true);
        await server.close();
        await dir.delete(recursive: true);
      });
      Future<List<int>> read(String url) async {
        final response = await (await client.getUrl(Uri.parse(url))).close();
        return response.expand((chunk) => chunk).toList();
      }

      final stream = await server.register(9, bytes.length);
      expect(await read(stream), bytes);
      expect(downloads, 1);
      expect(await read(stream), bytes);
      expect(downloads, 1);
      await server.close();
      server = TelegramStreamServer(request);
      final download = await server.register(9, bytes.length);
      expect(await read(download), bytes);
      expect(downloads, 1);
    },
  );
  test('refreshes a failed file reference from its message', () async {
    final dir = await Directory.systemTemp.createTemp('telegram_refresh');
    final file = File('${dir.path}/audio');
    await file.writeAsBytes([1, 2, 3]);
    var downloads = 0;
    final server = TelegramStreamServer((req) async {
      if (req['@type'] == 'getMessage') {
        return {
          'content': {
            'audio': {
              'audio': {'id': 77},
            },
          },
        };
      }
      if (req['@type'] == 'downloadFile') {
        downloads++;
        if (downloads == 1) {
          throw TdlibRequestException(400, 'Invalid file identifier');
        }
        expect(req['file_id'], 77);
        return {
          'local': {'path': file.path},
        };
      }
      if (req['@type'] == 'getFileDownloadedPrefixSize') return {'size': 3};
      throw StateError('unexpected');
    });
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.close();
      await dir.delete(recursive: true);
    });
    final uri = Uri.parse(await server.register(5, 3, chatId: 7, messageId: 9));
    final response = await (await client.getUrl(uri)).close();
    expect(await response.expand((chunk) => chunk).toList(), [1, 2, 3]);
    expect(downloads, 2);
  });

  test(
    'permanent TDLib errors do not repeatedly download the same file',
    () async {
      var downloads = 0;
      final server = TelegramStreamServer((req) async {
        if (req['@type'] == 'downloadFile') {
          downloads++;
          throw TdlibRequestException(400, 'File unavailable');
        }
        throw StateError('unexpected');
      });
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.close();
      });
      final uri = Uri.parse(await server.register(5, 3));
      for (var i = 0; i < 3; i++) {
        final response = await (await client.getUrl(uri)).close();
        expect(response.statusCode, HttpStatus.notFound);
        await response.drain<void>();
      }
      expect(downloads, 1);
    },
  );
  test('resolves cached remote file ids before streaming', () async {
    final dir = await Directory.systemTemp.createTemp('telegram_stale_id');
    final file = File('${dir.path}/audio');
    await file.writeAsBytes(List.generate(32, (index) => index));
    final calls = <Map<String, Object?>>[];
    final server = TelegramStreamServer((req) async {
      calls.add(req);
      switch (req['@type']) {
        case 'getRemoteFile':
          expect(req['remote_file_id'], 'stable-id');
          return {'id': 99};
        case 'downloadFile':
          expect(req['file_id'], 99);
          return {
            'local': {'path': file.path},
          };
        case 'getFileDownloadedPrefixSize':
          expect(req['file_id'], 99);
          return {'size': 32};
      }
      throw StateError('Unexpected request');
    });
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.close();
      await dir.delete(recursive: true);
    });
    final url = await server.register(
      5,
      32,
      remoteId: 'stable-id',
      chatId: 3,
      messageId: 4,
    );
    for (var i = 0; i < 2; i++) {
      final response = await (await client.getUrl(Uri.parse(url))).close();
      expect(
        await response.expand((chunk) => chunk).toList(),
        List.generate(32, (index) => index),
      );
    }
    expect(
      calls.where((call) => call['@type'] == 'getRemoteFile'),
      hasLength(1),
    );
  });

  test(
    'resolves file from message if the persistent id is unavailable',
    () async {
      final dir = await Directory.systemTemp.createTemp('telegram_message_id');
      final file = File('${dir.path}/audio');
      await file.writeAsBytes([1, 2, 3]);
      final server = TelegramStreamServer((req) async {
        if (req['@type'] == 'getMessage') {
          return {
            'content': {
              'audio': {
                'audio': {'id': 77},
              },
            },
          };
        }
        expect(req['file_id'], 77);
        return req['@type'] == 'downloadFile'
            ? {
                'local': {'path': file.path},
              }
            : {'size': 3};
      });
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.close();
        await dir.delete(recursive: true);
      });
      final url = await server.register(5, 3, chatId: 3, messageId: 4);
      final response = await (await client.getUrl(Uri.parse(url))).close();
      expect(await response.expand((chunk) => chunk).toList(), [1, 2, 3]);
    },
  );

  test('logs stream failures without exposing exception details', () async {
    TelegramPlaybackLog.clear();
    final server = TelegramStreamServer(
      (_) async => throw StateError('secret-proxy-token'),
    );
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.close();
      TelegramPlaybackLog.clear();
    });
    final uri = Uri.parse(await server.register(1, 128));
    final response = await (await client.getUrl(uri)).close();
    expect(response.statusCode, HttpStatus.badGateway);
    await response.drain<void>();
    final events = TelegramPlaybackLog.entries.value.join('\n');
    expect(events, contains('range failed type=StateError'));
    expect(events, isNot(contains('secret-proxy-token')));
    expect(events, isNot(contains(uri.path)));
  });
  test(
    'sends the first small range before downloading the next range',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'telegram_stream_start',
      );
      final file = File('${dir.path}/audio');
      await file.writeAsBytes(List.filled(100 * 1024, 7));
      final laterRange = Completer<void>();
      final requests = <Map<String, Object?>>[];
      final server = TelegramStreamServer((request) async {
        requests.add(request);
        if (request['@type'] == 'getFileDownloadedPrefixSize') {
          return {'size': 100 * 1024};
        }
        if ((request['offset'] as int) > 0) await laterRange.future;
        return {
          'local': {'path': file.path},
        };
      });
      final client = HttpClient();
      addTearDown(() async {
        if (!laterRange.isCompleted) laterRange.complete();
        client.close(force: true);
        await server.close();
        await dir.delete(recursive: true);
      });
      final url = await server.register(1, 100 * 1024);
      final response = await (await client.getUrl(Uri.parse(url))).close();
      final stream = StreamIterator(response);
      expect(
        await stream.moveNext().timeout(const Duration(seconds: 2)),
        isTrue,
      );
      expect(stream.current, isNotEmpty);
      expect(
        requests.firstWhere((item) => item['@type'] == 'downloadFile')['limit'],
        32 * 1024,
      );
      laterRange.complete();
      await stream.cancel();
    },
  );
  test('concurrent registrations use one local server', () async {
    final server = TelegramStreamServer((_) async => {});
    addTearDown(server.close);
    final urls = await Future.wait([
      server.register(1, 10),
      server.register(2, 10),
      server.register(3, 10),
    ]);
    expect(urls.map((url) => Uri.parse(url).port).toSet(), hasLength(1));
  });
  test('serves seek ranges using TDLib offsets', () async {
    final dir = await Directory.systemTemp.createTemp('telegram_stream');
    final file = File('${dir.path}/audio');
    await file.writeAsBytes(List.generate(256, (i) => i));
    final requests = <Map<String, Object?>>[];
    var downloaded = false;
    final server = TelegramStreamServer((request) async {
      requests.add(request);
      if (request['@type'] == 'getFileDownloadedPrefixSize') {
        return {'size': downloaded ? 10 : 0};
      }
      if (request['@type'] == 'downloadFile') downloaded = true;
      return {
        'local': {'path': file.path},
      };
    });
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.close();
      await dir.delete(recursive: true);
    });
    final url = await server.register(12, 256);
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=100-109');
    final response = await request.close();
    expect(response.statusCode, 206);
    expect(
      response.headers.value(HttpHeaders.contentRangeHeader),
      'bytes 100-109/256',
    );
    expect(
      await response.expand((chunk) => chunk).toList(),
      List.generate(10, (i) => i + 100),
    );
    final download = requests.firstWhere(
      (item) => item['@type'] == 'downloadFile',
    );
    expect(download['offset'], 100);
    expect(download['limit'], 10);
  });
  test(
    'prebuffers the predicted Telegram track once, with bounded low priority',
    () async {
      final calls = <Map<String, Object?>>[];
      final started = Completer<void>();
      final finish = Completer<void>();
      final server = TelegramStreamServer((request) async {
        calls.add(request);
        if (request['@type'] == 'downloadFile') {
          started.complete();
          await finish.future;
        }
        return {};
      }, prebufferDelay: Duration.zero);
      final player = PlaybackController(backend: FakeAudioBackend());
      addTearDown(() async {
        if (!finish.isCompleted) finish.complete();
        player.dispose();
        await server.close();
      });
      final next = await server.register(42, 1024 * 1024);
      await player.loadQueue([
        const LocalTrack(name: 'local', path: '/local'),
        LocalTrack(name: 'next', path: next, telegramFileId: 42),
      ]);
      server.updatePrebuffer(player);
      await started.future.timeout(const Duration(seconds: 2));
      server.updatePrebuffer(player);
      final call = calls.singleWhere((c) => c['@type'] == 'downloadFile');
      expect(call['file_id'], 42);
      expect(call['offset'], 0);
      expect(call['limit'], 256 * 1024);
      expect(call['priority'], 1);
      expect(call['synchronous'], true);
      finish.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls.where((c) => c['@type'] == 'downloadFile'), hasLength(1));
    },
  );

  test('prebuffer never blocks foreground ranges and only follows the latest next track', () async {
    final dir = await Directory.systemTemp.createTemp('prebuffer_priority');
    final audio = File('${dir.path}/audio');
    await audio.writeAsBytes([1, 2, 3]);
    final started = Completer<void>();
    final finish = Completer<void>();
    final calls = <Map<String, Object?>>[];
    final server = TelegramStreamServer((req) async {
      calls.add(req);
      if (req['@type'] == 'downloadFile' &&
          req['priority'] == 1 &&
          req['file_id'] == 2) {
        started.complete();
        await finish.future;
        return {};
      }
      if (req['@type'] == 'downloadFile' && req['priority'] == 32) {
        return {
          'local': {'path': audio.path},
        };
      }
      if (req['@type'] == 'getFileDownloadedPrefixSize') return {'size': 3};
      return {};
    }, prebufferDelay: Duration.zero);
    final player = PlaybackController(backend: FakeAudioBackend());
    final client = HttpClient();
    addTearDown(() async {
      if (!finish.isCompleted) finish.complete();
      client.close(force: true);
      player.dispose();
      await server.close();
      await dir.delete(recursive: true);
    });
    final two = await server.register(2, 3);
    final three = await server.register(3, 3);
    final four = await server.register(4, 3);
    await player.loadQueue([
      const LocalTrack(name: 'one', path: '/one'),
      LocalTrack(name: 'two', path: two),
      LocalTrack(name: 'three', path: three),
      LocalTrack(name: 'four', path: four),
    ]);
    server.updatePrebuffer(player);
    await started.future.timeout(const Duration(seconds: 2));
    final response = await (await client.getUrl(Uri.parse(four)))
        .close()
        .timeout(const Duration(seconds: 2));
    expect(await response.expand((bytes) => bytes).toList(), [1, 2, 3]);
    await player.playTrackAt(1);
    server.updatePrebuffer(player);
    await player.playTrackAt(2);
    server.updatePrebuffer(player);
    finish.complete();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(calls.where((c) => c['priority'] == 1).map((c) => c['file_id']), [
      2,
      4,
    ]);
  });
  test(
    'prebuffer respects pause, repeat-one, shuffle and local next tracks',
    () async {
      final requests = <Map<String, Object?>>[];
      final server = TelegramStreamServer((request) async {
        requests.add(request);
        return {};
      }, prebufferDelay: Duration.zero);
      final player = PlaybackController(backend: FakeAudioBackend());
      addTearDown(() async {
        player.dispose();
        await server.close();
      });
      final a = await server.register(1, 500);
      final b = await server.register(2, 700);
      await player.loadQueue([
        const LocalTrack(name: 'local', path: '/local'),
        LocalTrack(name: 'a', path: a),
        LocalTrack(name: 'b', path: b),
      ], autoplay: false);
      server.updatePrebuffer(player);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(requests, isEmpty);
      await player.play();
      player.setRepeat(true);
      server.updatePrebuffer(player);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(requests, isEmpty);
      player.setShuffle(true);
      final expected = player.nextIndex == 1 ? 1 : 2;
      server.updatePrebuffer(player);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(requests.single['file_id'], expected);
      expect(requests.single['limit'], expected == 1 ? 500 : 700);
      await player.pause();
      server.updatePrebuffer(player);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(requests, hasLength(1));
    },
  );
}
