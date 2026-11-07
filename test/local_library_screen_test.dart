import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/local_library_screen.dart';
import 'package:musicgram/playback_controller.dart';

void main() {
  testWidgets('opening a category directly returns to the player on back', (
    tester,
  ) async {
    final library = LocalLibraryScreen(
      tracks: const [LocalTrack(name: 'Song', path: '/song', album: 'Album')],
      playlists: Future.value([]),
      onPlay: (_, _) async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (pageContext) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (pageContext.mounted) {
                        library.openCategory(pageContext, 'Albums');
                      }
                    });
                    return library;
                  },
                ),
              );
            },
            child: const Text('Player'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Player'));
    await tester.pumpAndSettle();
    expect(find.text('Albums'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Player'), findsOneWidget);
    expect(find.text('Local music'), findsNothing);
  });
  testWidgets('local view exposes Telegram source switch', (tester) async {
    var switched = false;
    await tester.pumpWidget(
      MaterialApp(
        home: LocalLibraryScreen(
          tracks: const [],
          playlists: Future.value([]),
          onPlay: (_, _) async {},
          onOpenTelegram: () => switched = true,
        ),
      ),
    );
    await tester.tap(find.text('Telegram'));
    expect(switched, isTrue);
  });
  testWidgets('shows created local playlists below categories', (tester) async {
    final track = const LocalTrack(name: 'Song', path: '/song');
    await tester.pumpWidget(
      MaterialApp(
        home: LocalLibraryScreen(
          tracks: [track],
          playlists: Future.value([
            {
              'name': 'Favorites',
              'type': 'local',
              'tracks': [
                {'name': 'Song', 'path': '/song'},
              ],
            },
            {'name': 'Remote', 'type': 'telegram', 'tracks': []},
          ]),
          onPlay: (songs, index) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Favorites'), 200);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Remote'), findsNothing);
    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    expect(find.text('Song'), findsOneWidget);
  });
  testWidgets('browses genres and selects a song', (tester) async {
    final tracks = [
      const LocalTrack(
        name: 'Song',
        path: '/song',
        artist: 'Artist',
        genre: 'Rock',
      ),
    ];
    var selected = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: LocalLibraryScreen(
          tracks: tracks,
          onPlay: (songs, index) async {
            selected = index;
          },
        ),
      ),
    );
    await tester.tap(find.text('Genres'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Song'));
    await tester.pumpAndSettle();
    expect(selected, 0);
  });
}
