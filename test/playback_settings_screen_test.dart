import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/playback_settings.dart';
import 'package:musicgram/playback_settings_screen.dart';

void main() {
  testWidgets('groups options and saves changed playback behavior', (
    tester,
  ) async {
    PlaybackSettings? saved;
    PlaybackSettings? applied;
    await tester.pumpWidget(
      MaterialApp(
        home: PlaybackSettingsScreen(
          loadSettings: () async => PlaybackSettings(),
          saveSettings: (settings) async {
            saved = settings;
          },
          onSaved: (settings) => applied = settings,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('On launch'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Swipe artwork to change tracks'),
      200,
    );
    await tester.tap(find.text('Swipe artwork to change tracks'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Restart after 3 seconds'), 150);
    await tester.tap(find.text('Restart after 3 seconds'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restart after 5 seconds').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Save changes'), 150);
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(saved?.artworkSwipe, isFalse);
    expect(saved?.previousRestartSeconds, 5);
    expect(applied, same(saved));
  });
}
