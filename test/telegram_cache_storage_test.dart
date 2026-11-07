import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/telegram_cache_storage.dart';

void main() {
  test('clear removes only Telegram index files', () async {
    final dir = await Directory.systemTemp.createTemp('telegram_cache_storage');
    addTearDown(() => dir.delete(recursive: true));
    final index = File('${dir.path}/telegram_music_42.json');
    final otherIndex = File('${dir.path}/telegram_music_7.json');
    final playlist = File('${dir.path}/playlists.json');
    final song = File('${dir.path}/song.mp3');
    await index.writeAsString('1234');
    await otherIndex.writeAsString('123');
    await playlist.writeAsString('playlist');
    await song.writeAsString('audio');
    final cache = TelegramCacheStorage(directory: () async => dir);
    expect(await cache.size(), 7);
    await cache.clear();
    expect(await index.exists(), isFalse);
    expect(await otherIndex.exists(), isFalse);
    expect(await playlist.exists(), isTrue);
    expect(await song.exists(), isTrue);
    expect(await cache.size(), 0);
  });
}
