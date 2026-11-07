import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/telegram_audio_cache.dart';

void main() {
  test('counts audio and document cache across storage groups', () async {
    final cache = TelegramAudioCache(
      (request) async => {
        '@type': 'storageStatistics',
        'by_chat': [
          {
            'by_file_type': [
              {
                'file_type': {'@type': 'fileTypeAudio'},
                'size': 100,
              },
              {
                'file_type': {'@type': 'fileTypePhoto'},
                'size': 500,
              },
            ],
          },
          {
            'by_file_type': [
              {
                'file_type': {'@type': 'fileTypeDocument'},
                'size': 40,
              },
            ],
          },
        ],
      },
    );
    expect(await cache.size(), 140);
  });

  test(
    'clear targets audio and documents without touching saved downloads',
    () async {
      Map<String, Object?>? sent;
      final cache = TelegramAudioCache((request) async {
        sent = request;
        return {'@type': 'storageStatistics', 'size': 123};
      });
      expect(await cache.clear(), 123);
      expect(sent!['@type'], 'optimizeStorage');
      expect(sent!['size'], 0);
      expect(sent!['immunity_delay'], 0);
      expect(sent!['file_types'], [
        {'@type': 'fileTypeAudio'},
        {'@type': 'fileTypeDocument'},
      ]);
    },
  );
  test('chat usage is sorted by audio and document bytes', () async {
    final cache = TelegramAudioCache(
      (request) async => {
        '@type': 'storageStatistics',
        'by_chat': [
          {
            'chat_id': 1,
            'by_file_type': [
              {
                'file_type': {'@type': 'fileTypeAudio'},
                'size': 10,
              },
              {
                'file_type': {'@type': 'fileTypePhoto'},
                'size': 999,
              },
            ],
          },
          {
            'chat_id': 2,
            'by_file_type': [
              {
                'file_type': {'@type': 'fileTypeDocument'},
                'size': 50,
              },
            ],
          },
          {
            'chat_id': 0,
            'by_file_type': [
              {
                'file_type': {'@type': 'fileTypeAudio'},
                'size': 20,
              },
            ],
          },
        ],
      },
    );
    final chats = await cache.byChat();
    expect(chats.map((c) => c.chatId), [2, 0, 1]);
    expect(chats.map((c) => c.bytes), [50, 20, 10]);
  });

  test('clearing one chat sends only its chat identifier', () async {
    Map<String, Object?>? sent;
    final cache = TelegramAudioCache((request) async {
      sent = request;
      return {'@type': 'storageStatistics', 'size': 10};
    });
    await cache.clearChat(123);
    expect(sent!['chat_ids'], [123]);
    expect(() => cache.clearChat(0), throwsArgumentError);
  });
}
