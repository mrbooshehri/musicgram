import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/playlist_store.dart';

void main() {
  test(
    'favorites are saved separately for local and Telegram accounts',
    () async {
      final dir = await Directory.systemTemp.createTemp('musicgram_favorites_');
      addTearDown(() => dir.delete(recursive: true));
      var session = 'account_a';
      PlaylistStore store() => PlaylistStore(
        directory: () async => dir,
        sessionId: () async => session,
        telegramAccessible: () => true,
      );
      final local = <String, dynamic>{'path': '/song.mp3', 'name': 'Song'};
      final telegram = <String, dynamic>{'chat_id': 3, 'id': 4};
      expect(await store().toggleFavorite(local, telegram: false), isTrue);
      expect(await store().toggleFavorite(telegram, telegram: true), isTrue);
      expect(await store().isFavorite(local, telegram: false), isTrue);
      expect(await store().isFavorite(telegram, telegram: true), isTrue);
      session = 'account_b';
      expect(await store().isFavorite(local, telegram: false), isTrue);
      expect(await store().isFavorite(telegram, telegram: true), isFalse);
      session = 'account_a';
      expect(await store().toggleFavorite(telegram, telegram: true), isFalse);
      expect(await store().isFavorite(telegram, telegram: true), isFalse);
    },
  );
}
