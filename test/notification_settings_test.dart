import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:musicgram/main.dart';
import 'package:musicgram/notification_settings.dart';
import 'package:musicgram/playback_controller.dart';

import 'fake_audio_backend.dart';

void main() {
  test(
    'publishes generated artwork for a song without embedded artwork',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      NotificationSettings.showArtwork.value = true;
      final player = PlaybackController(backend: FakeAudioBackend());
      String? generatedFor;
      final handler = PlayerAudioHandler(
        player,
        generateArtwork: (track) async {
          generatedFor = track.path;
          return '/tmp/generated-cover.png';
        },
        shareArtwork: (path) async =>
            Uri.parse('content://com.example.musicgram.artwork/generated'),
      );
      addTearDown(() {
        handler.dispose();
        player.dispose();
        NotificationSettings.showArtwork.value = true;
      });
      await player.loadQueue(const [
        LocalTrack(name: 'No cover', path: '/no-cover.mp3'),
      ], autoplay: false);
      for (var i = 0; i < 20 && handler.mediaItem.value?.artUri == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(generatedFor, '/no-cover.mp3');
      expect(
        handler.mediaItem.value?.artUri,
        Uri.parse('content://com.example.musicgram.artwork/generated'),
      );
      NotificationSettings.showArtwork.value = false;
      expect(handler.mediaItem.value?.artUri, isNull);
    },
  );

  test('media artwork follows preference and current track', () async {
    final directory = await Directory.systemTemp.createTemp('notification_art');
    final image = File('${directory.path}/art.jpg');
    await image.writeAsBytes([1, 2, 3]);
    NotificationSettings.showArtwork.value = true;
    final playback = PlaybackController(backend: FakeAudioBackend());
    final handler = PlayerAudioHandler(playback);
    addTearDown(() async {
      handler.dispose();
      playback.dispose();
      NotificationSettings.showArtwork.value = true;
      await directory.delete(recursive: true);
    });
    await playback.loadQueue([
      LocalTrack(
        name: 'Song',
        path: '/song',
        telegramFileId: 1,
        telegramMessage: {
          'content': {
            'audio': {
              'album_cover_thumbnail': {
                'file': {
                  'local': {
                    'is_downloading_completed': true,
                    'path': image.path,
                  },
                },
              },
            },
          },
        },
      ),
    ]);
    for (var i = 0; i < 20 && handler.mediaItem.value?.artUri == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(handler.mediaItem.value?.artUri, Uri.file(image.path));
    NotificationSettings.showArtwork.value = false;
    expect(handler.mediaItem.value?.artUri, isNull);
    NotificationSettings.showArtwork.value = true;
    for (var i = 0; i < 20 && handler.mediaItem.value?.artUri == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(handler.mediaItem.value?.artUri, Uri.file(image.path));
  });

  test('downloads available Telegram artwork and ignores late results when disabled', () async {
    final download = Completer<Map<String, dynamic>>();
    NotificationSettings.showArtwork.value = true;
    final playback = PlaybackController(backend: FakeAudioBackend());
    final handler = PlayerAudioHandler(
      playback,
      telegramRequest: (request) => download.future,
    );
    addTearDown(() {
      handler.dispose();
      playback.dispose();
      NotificationSettings.showArtwork.value = true;
    });
    await playback.loadQueue(const [
      LocalTrack(
        name: 'Song',
        path: '/song',
        telegramFileId: 1,
        telegramMessage: {
          'content': {
            'audio': {
              'album_cover_thumbnail': {
                'file': {'id': 23},
              },
            },
          },
        },
      ),
    ]);
    NotificationSettings.showArtwork.value = false;
    download.complete({
      'local': {'is_downloading_completed': true, 'path': '/tmp/cover.jpg'},
    });
    await Future<void>.delayed(Duration.zero);
    expect(handler.mediaItem.value?.artUri, isNull);
    NotificationSettings.showArtwork.value = true;
    await Future<void>.delayed(Duration.zero);
    expect(handler.mediaItem.value?.artUri, Uri.file('/tmp/cover.jpg'));
  });
  test(
    'publishes a shareable artwork URI for the current media session',
    () async {
      final directory = await Directory.systemTemp.createTemp('car_art');
      final image = File('${directory.path}/cover.jpg');
      await image.writeAsBytes([1, 2, 3]);
      final player = PlaybackController(backend: FakeAudioBackend());
      final handler = PlayerAudioHandler(
        player,
        shareArtwork: (path) async {
          expect(path, image.path);
          return Uri.parse('content://com.example.musicgram.artwork/cover');
        },
      );
      addTearDown(() async {
        handler.dispose();
        player.dispose();
        await directory.delete(recursive: true);
      });
      await player.loadQueue([
        LocalTrack(
          name: 'Song',
          path: '/song',
          telegramFileId: 1,
          telegramMessage: {
            'content': {
              'audio': {
                'album_cover_thumbnail': {
                  'file': {
                    'local': {
                      'is_downloading_completed': true,
                      'path': image.path,
                    },
                  },
                },
              },
            },
          },
        ),
      ]);
      for (var i = 0; i < 20 && handler.mediaItem.value?.artUri == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(handler.mediaItem.value?.artUri?.scheme, 'content');
    },
  );
  test('compact skip preference updates media session and persists with artwork setting', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    String? stored;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'write') stored = call.arguments['value'] as String;
      if (call.method == 'read') return stored;
      return null;
    });
    final player = PlaybackController(backend: FakeAudioBackend());
    final handler = PlayerAudioHandler(player);
    addTearDown(() {
      handler.dispose();
      player.dispose();
      NotificationSettings.showArtwork.value = true;
      NotificationSettings.showCompactSkip.value = true;
      messenger.setMockMethodCallHandler(channel, null);
    });
    await NotificationSettings.save(false);
    await NotificationSettings.saveCompactSkip(false);
    expect(handler.playbackState.value.androidCompactActionIndices, [1]);
    expect(handler.playbackState.value.controls.length, 3);
    NotificationSettings.showArtwork.value = true;
    NotificationSettings.showCompactSkip.value = true;
    await NotificationSettings.load();
    expect(NotificationSettings.showArtwork.value, isFalse);
    expect(NotificationSettings.showCompactSkip.value, isFalse);
    expect(handler.playbackState.value.androidCompactActionIndices, [1]);
  });
}
