import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/main.dart';
import 'package:musicgram/playback_controller.dart';

import 'fake_audio_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'car browser shows local songs and selects the requested track',
    () async {
      final backend = FakeAudioBackend();
      final player = PlaybackController(backend: backend);
      final handler = PlayerAudioHandler(
        player,
        localLibrary: () async => const [
          LocalTrack(
            name: 'one.mp3',
            path: '/one',
            title: 'First',
            artist: 'Artist',
          ),
          LocalTrack(name: 'two.mp3', path: '/two', title: 'Second'),
        ],
      );
      addTearDown(() {
        handler.dispose();
        player.dispose();
      });
      final root = await handler.getChildren(AudioService.browsableRootId);
      expect(
        root.map((item) => item.title),
        containsAll(['Current queue', 'All songs']),
      );
      final songs = await handler.getChildren('car:local');
      expect(songs.map((item) => item.title), ['First', 'Second']);
      expect(songs.first.artist, 'Artist');
      await handler.playFromMediaId(songs[1].id);
      expect(player.currentTrack?.path, '/two');
      expect(player.queue.length, 2);
      expect(backend.lastSource, '/two');
      expect(player.isPlaying, isTrue);
    },
  );

  test(
    'car queue selection plays the existing queue and ignores stale IDs',
    () async {
      final backend = FakeAudioBackend();
      final player = PlaybackController(backend: backend);
      final handler = PlayerAudioHandler(player, localLibrary: () async => []);
      addTearDown(() {
        handler.dispose();
        player.dispose();
      });
      await player.loadQueue(const [
        LocalTrack(name: 'Telegram', path: 'http://127.0.0.1/stream'),
        LocalTrack(name: 'Local', path: '/local'),
      ], autoplay: false);
      final queue = await handler.getChildren('car:queue');
      await handler.playFromMediaId(queue.first.id);
      expect(player.currentTrack?.name, 'Telegram');
      expect(backend.lastSource, 'http://127.0.0.1/stream');
      await player.loadQueue(const [
        LocalTrack(name: 'Other', path: '/other'),
      ], autoplay: false);
      await handler.playFromMediaId(queue.last.id);
      expect(player.currentTrack?.path, '/other');
    },
  );
  test('car browses Telegram playlists and plays a selected song', () async {
    final player = PlaybackController(backend: FakeAudioBackend());
    final messages = [
      <String, dynamic>{
        'id': 10,
        'content': {
          'audio': {'title': 'First', 'performer': 'Artist'},
        },
      },
      <String, dynamic>{
        'id': 11,
        'content': {
          'document': {'file_name': 'Second.mp3'},
        },
      },
    ];
    List<Map<String, dynamic>>? played;
    int? selected;
    String? playlistName;
    final handler = PlayerAudioHandler(
      player,
      telegramLibrary: () async => [
        CarTelegramPlaylist(
          id: 'chat:-100',
          title: 'My chat',
          tracks: messages,
        ),
      ],
      playTelegram: (tracks, index, title) async {
        played = tracks;
        selected = index;
        playlistName = title;
      },
    );
    addTearDown(() {
      handler.dispose();
      player.dispose();
    });
    final root = await handler.getChildren(AudioService.browsableRootId);
    expect(root.map((item) => item.title), contains('Telegram'));
    final playlists = await handler.getChildren('car:telegram');
    expect(playlists.single.title, 'My chat');
    final tracks = await handler.getChildren(playlists.single.id);
    expect(tracks.map((item) => item.title), ['First', 'Second.mp3']);
    expect(tracks.first.artist, 'Artist');
    await handler.playFromMediaId(tracks.last.id);
    expect(played, messages);
    expect(selected, 1);
    expect(playlistName, 'My chat');
  });
}
