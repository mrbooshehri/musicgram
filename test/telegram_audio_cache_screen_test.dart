import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/telegram_audio_cache_screen.dart';

void main() {
  testWidgets('shows chats by size and clears only the chosen chat', (
    tester,
  ) async {
    final requests = <Map<String, Object?>>[];
    var cleared = false;
    Future<Map<String, dynamic>> request(Map<String, Object?> input) async {
      requests.add(input);
      switch (input['@type']) {
        case 'getChat':
          return {'title': input['chat_id'] == 1 ? 'Small chat' : 'Large chat'};
        case 'getStorageStatistics':
          return {
            '@type': 'storageStatistics',
            'by_chat': [
              {
                'chat_id': 1,
                'by_file_type': [
                  {
                    'file_type': {'@type': 'fileTypeAudio'},
                    'size': 10,
                  },
                ],
              },
              if (!cleared)
                {
                  'chat_id': 2,
                  'by_file_type': [
                    {
                      'file_type': {'@type': 'fileTypeAudio'},
                      'size': 5000,
                    },
                  ],
                },
            ],
          };
        case 'optimizeStorage':
          cleared = true;
          return {'@type': 'storageStatistics', 'size': 5000};
        default:
          throw StateError('Unexpected request');
      }
    }

    await tester.pumpWidget(
      MaterialApp(home: TelegramAudioCacheScreen(request: request)),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Large chat')).dy,
      lessThan(tester.getTopLeft(find.text('Small chat')).dy),
    );
    await tester.tap(find.widgetWithText(ListTile, 'Large chat').findClear());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear cache'));
    await tester.pumpAndSettle();
    expect(
      requests.singleWhere((r) => r['@type'] == 'optimizeStorage')['chat_ids'],
      [2],
    );
    expect(find.text('Large chat'), findsNothing);
    expect(find.text('Small chat'), findsOneWidget);
  });
}

extension on Finder {
  Finder findClear() => find.descendant(of: this, matching: find.text('Clear'));
}
