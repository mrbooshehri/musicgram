import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/lyrics.dart';
import 'package:musicgram/lyrics_sheet.dart';
import 'package:musicgram/playback_controller.dart';

import 'fake_audio_backend.dart';

class FakeLyricsService extends LyricsService {
  String? lastQuery;
  @override
  Future<List<LyricsRecord>> search({
    String? query,
    String? title,
    String? artist,
  }) async {
    lastQuery = query;
    return [
      LyricsRecord.fromJson({
        'id': 1,
        'trackName': 'Song',
        'artistName': 'Artist',
        'syncedLyrics': '[00:01.00]Hello',
      }),
    ];
  }
}

class FakeLyricsCache extends LyricsCache {
  final values = <String, LyricsRecord>{};
  @override
  Future<LyricsRecord?> load(String key) async => values[key];
  @override
  Future<void> save(String key, LyricsRecord record) async {
    values[key] = record;
  }
}

void main() {
  testWidgets('search result selection is cached and lyrics are displayed', (
    tester,
  ) async {
    final player = PlaybackController(backend: FakeAudioBackend());
    await player.loadQueue(const [
      LocalTrack(name: 'Song', path: '/song', artist: 'Artist'),
    ], autoplay: false);
    final cache = FakeLyricsCache();
    final service = FakeLyricsService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LyricsSheet(player: player, cache: cache, service: service),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Search manual'), findsOneWidget);
    expect(find.text('Song'), findsOneWidget);
    await tester.tap(find.text('Song'));
    await tester.pumpAndSettle();
    expect(find.text('Hello'), findsOneWidget);
    expect(cache.values['/song']?.trackName, 'Song');
    await player.seek(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.text('Hello')).style?.fontWeight,
      FontWeight.bold,
    );
    await tester.tap(find.text('Search manual'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Another title');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(service.lastQuery, 'Another title');
    await tester.pumpWidget(const SizedBox());
    player.dispose();
  });
}
