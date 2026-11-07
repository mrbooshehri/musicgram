import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/playlist_queue_settings_screen.dart';
import 'package:musicgram/queue_shortcut_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('opening view is saved and restored without a shortcut file', () async {
    final dir = await Directory.systemTemp.createTemp('musicgram_queue_test');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => dir.path);
    try {
      await QueueShortcutSettings.saveOpeningView('playlists');
      QueueShortcutSettings.openingView.value = 'queue';
      await QueueShortcutSettings.load();
      expect(QueueShortcutSettings.openingView.value, 'playlists');
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      QueueShortcutSettings.openingView.value = 'queue';
      await dir.delete(recursive: true);
    }
  });
  testWidgets('settings page opens playlist management', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: PlaylistQueueSettingsScreen(
          openPlaylists: () => opened = true,
          localPlaylistsAvailable: true,
        ),
      ),
    );
    await tester.tap(find.text('Manage playlists'));
    expect(opened, isTrue);
    expect(find.text('Queue shortcuts'), findsOneWidget);
    expect(find.text('Current queue'), findsOneWidget);
  });

  testWidgets('reset restores default shortcut order', (tester) async {
    QueueShortcutSettings.order.value = QueueShortcutSettings.defaults.reversed
        .toList();
    addTearDown(
      () => QueueShortcutSettings.order.value = List.of(
        QueueShortcutSettings.defaults,
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(home: QueueShortcutSettingsScreen()),
    );
    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(
      tester.getTopLeft(find.text('All songs')).dy,
      lessThan(tester.getTopLeft(find.text('Artists')).dy),
    );
  });
}
