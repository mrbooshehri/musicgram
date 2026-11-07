import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/telegram_artwork.dart';

void main() {
  test('resolves cached thumbnail ID before requesting artwork', () async {
    final calls = <Map<String, Object?>>[];
    final path = await resolveTelegramArtwork(
      {
        'content': {
          'audio': {
            'album_cover_thumbnail': {
              'file': {
                'id': 3,
                'remote': {'id': 'persistent'},
              },
            },
          },
        },
      },
      (request) async {
        calls.add(request);
        if (request['@type'] == 'getRemoteFile') return {'id': 42};
        return {
          'local': {'is_downloading_completed': true, 'path': '/tmp/cover.jpg'},
        };
      },
    );
    expect(path, '/tmp/cover.jpg');
    expect(calls.last['file_id'], 42);
  });
  testWidgets('requests the Telegram cover thumbnail', (tester) async {
    final calls = <Map<String, Object?>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: TelegramArtwork(
          message: {
            'content': {
              'audio': {
                'album_cover_thumbnail': {
                  'file': {'id': 23},
                },
              },
            },
          },
          request: (request) async {
            calls.add(request);
            return {
              'local': {'is_downloading_completed': false, 'path': ''},
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls.single['@type'], 'downloadFile');
    expect(calls.single['file_id'], 23);
    expect(find.byIcon(Icons.music_note), findsOneWidget);
  });
  testWidgets(
    'same Telegram artwork keeps its request across playback rebuilds',
    (tester) async {
      final download = Completer<Map<String, dynamic>>();
      var calls = 0;
      final message = <String, dynamic>{
        'chat_id': 2,
        'id': 9,
        'content': {
          'audio': {
            'album_cover_thumbnail': {
              'file': {'id': 23},
            },
          },
        },
      };
      Future<Map<String, dynamic>> request(Map<String, Object?> _) {
        calls++;
        return download.future;
      }

      Widget view(int tick, {int fileId = 23}) => MaterialApp(
        home: Column(
          children: [
            Text('$tick'),
            TelegramArtwork(
              message: {
                ...message,
                'content': {
                  'audio': {
                    'album_cover_thumbnail': {
                      'file': {'id': fileId},
                    },
                  },
                },
              },
              request: request,
            ),
          ],
        ),
      );
      await tester.pumpWidget(view(0));
      await tester.pump();
      expect(calls, 1);
      for (var i = 1; i <= 4; i++) {
        await tester.pumpWidget(view(i));
        await tester.pump();
      }
      expect(calls, 1);
      download.complete({
        'local': {'is_downloading_completed': false, 'path': ''},
      });
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.music_note), findsOneWidget);
      await tester.pumpWidget(view(5));
      await tester.pump();
      expect(calls, 1);
      await tester.pumpWidget(view(6, fileId: 24));
      await tester.pump();
      expect(calls, 2);
    },
  );
}
