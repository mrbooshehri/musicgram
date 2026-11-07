import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/local_category_sheet.dart';
import 'package:musicgram/playback_controller.dart';

void main() {
  testWidgets('category back requests return to queue', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showModalBottomSheet<bool>(
                  context: context,
                  builder: (_) => LocalCategorySheet(
                    category: 'Artists',
                    tracks: const [],
                    onPlay: (_, _) async {},
                  ),
                );
              },
              child: const Text('Queue'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Queue'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
  testWidgets('playlist selection stays in the sheet and plays its songs', (
    tester,
  ) async {
    var played = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalCategorySheet(
            category: 'Playlists',
            tracks: const [LocalTrack(path: '/one', name: 'One')],
            playlists: Future.value([
              {
                'type': 'local',
                'name': 'Favorites',
                'tracks': [
                  {'path': '/one', 'name': 'One'},
                ],
              },
            ]),
            onPlay: (tracks, index) async {
              played = tracks[index].path == '/one';
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    expect(find.text('One'), findsOneWidget);
    await tester.tap(find.text('One'));
    await tester.pumpAndSettle();
    expect(played, isTrue);
  });
  testWidgets(
    'search filters artists and their songs without changing playback index',
    (tester) async {
      List<LocalTrack>? played;
      int? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalCategorySheet(
              category: 'Artists',
              tracks: const [
                LocalTrack(path: '/one', name: 'First', artist: 'Queen'),
                LocalTrack(path: '/two', name: 'Second', artist: 'Queen'),
                LocalTrack(
                  path: '/three',
                  name: 'Other',
                  artist: 'Other artist',
                ),
              ],
              onPlay: (tracks, index) async {
                played = tracks;
                chosen = index;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'qen');
      await tester.pump();
      expect(find.text('Queen'), findsOneWidget);
      expect(find.text('Other artist'), findsNothing);
      await tester.tap(find.text('Queen'));
      await tester.pump();
      expect(find.text('First'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'scnd');
      await tester.pump();
      expect(find.text('First'), findsNothing);
      await tester.tap(find.text('Second'));
      await tester.pumpAndSettle();
      expect(played?[chosen!].path, '/two');
    },
  );
}
