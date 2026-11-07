import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/playlist_store.dart';

void main() {
  test('stores local and Telegram playlists across reloads', () async {
    final dir = await Directory.systemTemp.createTemp('musicgram_playlists');
    addTearDown(() => dir.delete(recursive: true));
    final store = PlaylistStore(directory: () async => dir);
    expect(await store.load(), isEmpty);
    final playlists = <Map<String, dynamic>>[
      {'name': 'Local', 'type': 'local', 'tracks': []},
      {'name': 'Telegram', 'type': 'telegram', 'tracks': []},
    ];
    await store.save(playlists);
    expect(await store.load(), playlists);
  });
  test(
    'Telegram playlists are isolated while local playlists remain shared',
    () async {
      final dir = await Directory.systemTemp.createTemp('account_playlists');
      addTearDown(() => dir.delete(recursive: true));
      var active = 'legacy';
      final store = PlaylistStore(
        directory: () async => dir,
        sessionId: () async => active,
      );
      await store.save([
        {'name': 'Local', 'type': 'local', 'tracks': []},
        {'name': 'Legacy', 'type': 'telegram', 'tracks': []},
      ]);
      active = 'session_second';
      expect((await store.load()).map((p) => p['name']), ['Local']);
      await store.save([
        ...(await store.load()),
        {'name': 'Second', 'type': 'telegram', 'tracks': []},
      ]);
      expect((await store.load()).map((p) => p['name']), ['Local', 'Second']);
      active = 'legacy';
      expect((await store.load()).map((p) => p['name']), ['Local', 'Legacy']);
      active = 'session_second';
      await expectLater(store.save([]), throwsStateError);
      await store.load();
      await store.save([]);
      active = 'legacy';
      expect((await store.load()).map((p) => p['name']), ['Legacy']);
    },
  );
  test(
    'unverified session hides Telegram playlists and rejects stale saves',
    () async {
      final dir = await Directory.systemTemp.createTemp('playlist_unverified');
      addTearDown(() => dir.delete(recursive: true));
      var allowed = true;
      final store = PlaylistStore(
        directory: () async => dir,
        sessionId: () async => 'legacy',
        telegramAccessible: () => allowed,
      );
      await store.save([
        {'name': 'Local', 'type': 'local'},
        {'name': 'Telegram', 'type': 'telegram'},
      ]);
      final previous = await store.load();
      allowed = false;
      await expectLater(store.save(previous), throwsStateError);
      expect((await store.load()).map((e) => e['name']), ['Local']);
      await store.save([
        {'name': 'Local edited', 'type': 'local'},
      ]);
      allowed = true;
      expect((await store.load()).map((e) => e['name']), [
        'Local edited',
        'Telegram',
      ]);
    },
  );
}
