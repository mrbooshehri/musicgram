import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/downloaded_tracks.dart';

void main() {
  test(
    'download keys are isolated per session while preserving legacy keys',
    () {
      final message = <String, dynamic>{
        'chat_id': 2,
        'id': 3,
        'content': {
          'document': {'document': {}},
        },
      };
      expect(
        DownloadedTracks.keyFor(message, sessionId: 'legacy'),
        'message:2:3',
      );
      expect(
        DownloadedTracks.keyFor(message, sessionId: 'session_a'),
        'session:session_a:message:2:3',
      );
      expect(
        DownloadedTracks.keyFor(message, sessionId: 'session_b'),
        'session:session_b:message:2:3',
      );
    },
  );
  test('uses Telegram stable file identity, with a message fallback', () {
    expect(
      DownloadedTracks.keyFor({
        'chat_id': 2,
        'id': 3,
        'content': {
          'audio': {
            'audio': {
              'remote': {'unique_id': 'abc'},
            },
          },
        },
      }),
      'file:abc',
    );
    expect(
      DownloadedTracks.keyFor({
        'chat_id': 2,
        'id': 3,
        'content': {
          'document': {'document': {}},
        },
      }),
      'message:2:3',
    );
    expect(DownloadedTracks.keyFor({'content': {}}), isNull);
  });
}
