import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/music_library_settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const library = MethodChannel('musicgram/library');
  testWidgets(
    'adds and removes explicit paths without listing scanned folders',
    (tester) async {
      String? saved;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(storage, (call) async {
        if (call.method == 'read') return null;
        if (call.method == 'write') saved = call.arguments['value'] as String;
        return null;
      });
      messenger.setMockMethodCallHandler(
        library,
        (call) async => [
          {'path': '/storage/hidden-from-list/song.mp3'},
        ],
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(storage, null);
        messenger.setMockMethodCallHandler(library, null);
      });
      await tester.binding.setSurfaceSize(const Size(800, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(home: MusicLibrarySettingsScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 of 1 tracks match these settings'), findsOneWidget);
      await tester.tap(find.text('Include tracks with unknown duration'));
      await tester.pumpAndSettle();
      expect(find.text('0 of 1 tracks match these settings'), findsOneWidget);
      expect(find.text('/storage/hidden-from-list'), findsNothing);
      expect(find.text('No folders excluded.'), findsOneWidget);
      await tester.tap(find.text('Enter path'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '/storage/Podcasts/');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('/storage/Podcasts'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove excluded folder'));
      await tester.pumpAndSettle();
      expect(find.text('/storage/Podcasts'), findsNothing);
      await tester.tap(find.text('Enter path'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '/storage/Podcasts');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exclude Telegram audio'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final data = jsonDecode(saved!) as Map<String, dynamic>;
      expect(data['excludedFolders'], ['/storage/Podcasts']);
      expect(data['excludeTelegram'], true);
      expect(data['excludeWhatsApp'], true);
      expect(data['includeUnknownDuration'], false);
    },
  );
  testWidgets(
    'rescan applies the selected duration and reports matching tracks',
    (tester) async {
      String? saved;
      var applied = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(storage, (call) async {
        if (call.method == 'read') return saved;
        if (call.method == 'write') saved = call.arguments['value'] as String;
        return null;
      });
      messenger.setMockMethodCallHandler(
        library,
        (_) async => [
          {'path': '/music/short.mp3', 'duration': '5000'},
          {'path': '/music/song.mp3', 'duration': '180000'},
        ],
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(storage, null);
        messenger.setMockMethodCallHandler(library, null);
      });
      await tester.pumpWidget(
        MaterialApp(home: MusicLibrarySettingsScreen(onSaved: () => applied++)),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 of 2 tracks match these settings'), findsOneWidget);
      await tester.tap(find.text('No minimum'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 seconds').last);
      await tester.pumpAndSettle();
      expect(find.text('1 of 2 tracks match these settings'), findsOneWidget);
      await tester.tap(find.text('Rescan local music'));
      await tester.pumpAndSettle();
      expect((jsonDecode(saved!) as Map)['minimumSeconds'], 30);
      expect(applied, 1);
      expect(find.text('1 of 2 tracks match these settings'), findsOneWidget);
    },
  );
}
