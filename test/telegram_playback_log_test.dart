import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/telegram_playback_log.dart';

void main() {
  setUp(TelegramPlaybackLog.clear);
  tearDown(TelegramPlaybackLog.clear);

  test('bounds the session log', () {
    for (var i = 0; i < 305; i++) {
      TelegramPlaybackLog.record('event $i');
    }
    expect(TelegramPlaybackLog.entries.value.length, 300);
    expect(TelegramPlaybackLog.entries.value.first, contains('event 5'));
  });

  testWidgets('shows, copies, and clears playback diagnostics', (tester) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    TelegramPlaybackLog.record('Player source load started');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showTelegramPlaybackLog(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Player source load started'), findsOneWidget);
    await tester.tap(find.text('Copy log'));
    await tester.pump();
    expect(copied, contains('Player source load started'));
    await tester.tap(find.byTooltip('Clear playback log'));
    await tester.pump();
    expect(find.text('No playback events yet.'), findsOneWidget);
  });
}
