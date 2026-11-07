import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/diagnostics_logs_screen.dart';
import 'package:musicgram/playback_diagnostics.dart';
import 'package:musicgram/telegram_screen.dart';
import 'package:musicgram/log_timestamp.dart';
import 'package:musicgram/telegram_client.dart';

void main() {
  test('formats full local dates with millisecond precision', () {
    expect(
      logTimestamp(DateTime(2026, 1, 2, 3, 4, 5, 6)),
      '2026-01-02 03:04:05.006',
    );
  });
  test('records connection changes without opening Telegram settings', () {
    telegramConnectionLog.value = [];
    addTearDown(() => telegramConnectionLog.value = []);
    final client = TelegramClient.forTesting();
    client.updateConnectionInfo({
      '@type': 'updateConnectionState',
      'state': {'@type': 'connectionStateReady'},
    });
    expect(
      telegramConnectionLog.value.single,
      matches(
        RegExp(
          r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}  Connection: connectionStateReady$',
        ),
      ),
    );
    client.dispose();
  });
  testWidgets('opens each log page with fixed copy and clear actions', (
    tester,
  ) async {
    telegramConnectionLog.value = ['connection event'];
    PlaybackDiagnostics.entries.value = ['player error'];
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = call.arguments['text'] as String?;
          }
          return null;
        });
    addTearDown(() {
      telegramConnectionLog.value = [];
      PlaybackDiagnostics.entries.value = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    await tester.pumpWidget(const MaterialApp(home: DiagnosticsLogsScreen()));
    await tester.tap(find.text('Telegram connection'));
    await tester.pumpAndSettle();
    expect(find.text('connection event'), findsOneWidget);
    await tester.tap(find.text('Copy'));
    expect(copied, 'connection event');
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('No events yet.'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Player errors'));
    await tester.pumpAndSettle();
    expect(find.text('player error'), findsOneWidget);
  });

  testWidgets('opens at latest event and follows new events', (tester) async {
    telegramConnectionLog.value = List.generate(100, (i) => 'event $i');
    addTearDown(() => telegramConnectionLog.value = []);
    await tester.pumpWidget(const MaterialApp(home: DiagnosticsLogsScreen()));
    await tester.tap(find.text('Telegram connection'));
    await tester.pumpAndSettle();
    expect(find.text('event 99'), findsOneWidget);
    telegramConnectionLog.value = [
      ...telegramConnectionLog.value,
      'newest event',
    ];
    await tester.pumpAndSettle();
    expect(find.text('newest event'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);
  });
}
