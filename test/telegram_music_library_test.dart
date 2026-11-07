import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/telegram_music_library.dart';

void main() {
  test(
    'groups audio and music documents, paginates and removes duplicates',
    () async {
      final calls = <Map<String, Object?>>[];
      final library = TelegramMusicLibrary(
        request: (request) async {
          calls.add(request);
          final filter = request['filter'] as Map;
          if (filter['@type'] == 'searchMessagesFilterAudio') {
            if (request['offset'] == '') {
              return {
                'messages': [
                  {
                    'chat_id': 1,
                    'id': 2,
                    'content': {'@type': 'messageAudio'},
                  },
                ],
                'next_offset': 'next',
              };
            }
            return {
              'messages': [
                {
                  'chat_id': 1,
                  'id': 2,
                  'content': {'@type': 'messageAudio'},
                },
              ],
              'next_offset': '',
            };
          }
          return {
            'messages': [
              {
                'chat_id': 3,
                'id': 4,
                'content': {
                  '@type': 'messageDocument',
                  'document': {'file_name': 'song.MP3'},
                },
              },
              {
                'chat_id': 5,
                'id': 6,
                'content': {
                  '@type': 'messageDocument',
                  'document': {'file_name': 'notes.pdf'},
                },
              },
            ],
            'next_offset': '',
          };
        },
      );
      final result = await library.discover().last;
      expect(result.keys, containsAll([1, 3]));
      expect(result.containsKey(5), isFalse);
      expect(result[1], hasLength(1));
      expect(calls, hasLength(3));
    },
  );
}
