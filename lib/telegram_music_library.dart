import 'telegram_client.dart';

typedef TelegramRequest = Future<Map<String, dynamic>> Function(
  Map<String, Object?> request,
);

/// Discovers audio messages across chats. Secret chats are not searchable.
class TelegramMusicLibrary {
  TelegramMusicLibrary({TelegramRequest? request})
    : _request = request ?? TelegramClient.shared.request;

  final TelegramRequest _request;

  /// Scans only the selected chats; an incomplete scan never replaces cache.
  Stream<Map<int, List<Map<String, dynamic>>>> discoverChats(
    Set<int> chatIds,
  ) async* {
    final groups = <int, List<Map<String, dynamic>>>{};
    final seen = <String>{};
    for (final chatId in chatIds) {
      for (final filter in [
        'searchMessagesFilterAudio',
        'searchMessagesFilterDocument',
      ]) {
        var offset = 0;
        final offsets = <int>{};
        do {
          final response = await _request({
            '@type': 'searchChatMessages',
            'chat_id': chatId,
            'query': '',
            'from_message_id': offset,
            'offset': 0,
            'limit': 100,
            'filter': {'@type': filter},
          });
          final messages = response['messages'];
          if (messages is! List) {
            throw const FormatException('Invalid Telegram search response');
          }
          for (final item in messages) {
            if (item is! Map) continue;
            final message = Map<String, dynamic>.from(item);
            final id = message['id'];
            final content = message['content'];
            if (message['chat_id'] != chatId || id is! int || content is! Map) {
              continue;
            }
            final type = content['@type'];
            if (type == 'messageDocument') {
              final document = content['document'];
              if (document is! Map) continue;
              final mime = (document['mime_type'] as String? ?? '')
                  .toLowerCase();
              final name = (document['file_name'] as String? ?? '')
                  .toLowerCase();
              if (!mime.startsWith('audio/') &&
                  !RegExp(r'\.(mp3|m4a|aac|flac|ogg|opus|wav)$')
                      .hasMatch(name)) {
                continue;
              }
            } else if (type != 'messageAudio') {
              continue;
            }
            if (seen.add('$chatId:$id')) (groups[chatId] ??= []).add(message);
          }
          yield {
            for (final entry in groups.entries)
              entry.key: List.unmodifiable(entry.value),
          };
          final next = response['next_from_message_id'];
          if (next is! int || next < 0) {
            throw const FormatException('Invalid Telegram search offset');
          }
          offset = next;
          if (offset != 0 && !offsets.add(offset)) {
            throw const FormatException(
              'Telegram search returned a repeated offset',
            );
          }
        } while (offset != 0);
      }
    }
  }

  /// Each emitted batch groups discovered messages by Telegram chat ID.
  Stream<Map<int, List<Map<String, dynamic>>>> discover() async* {
    final groups = <int, List<Map<String, dynamic>>>{};
    final seen = <String>{};
    for (final filter in [
      'searchMessagesFilterAudio',
      'searchMessagesFilterDocument',
    ]) {
      var offset = '';
      final offsets = <String>{};
      do {
        final response = await _request({
          '@type': 'searchMessages',
          'chat_list': null,
          'query': '',
          'offset': offset,
          'limit': 100,
          'filter': {'@type': filter},
          'min_date': 0,
          'max_date': 0,
        });
        final messages = response['messages'];
        if (messages is! List) {
          throw const FormatException('Invalid Telegram search response');
        }
        for (final item in messages) {
          if (item is! Map) continue;
          final message = Map<String, dynamic>.from(item);
          final chat = message['chat_id'];
          final id = message['id'];
          final content = message['content'];
          if (chat is! int || id is! int || content is! Map) continue;
          final type = content['@type'];
          if (type == 'messageDocument') {
            final document = content['document'];
            if (document is! Map) continue;
            final mime = (document['mime_type'] as String? ?? '').toLowerCase();
            final name = (document['file_name'] as String? ?? '').toLowerCase();
            if (!mime.startsWith('audio/') &&
                !RegExp(r'\.(mp3|m4a|aac|flac|ogg|opus|wav)$').hasMatch(name)) {
              continue;
            }
          } else if (type != 'messageAudio') {
            continue;
          }
          if (seen.add('$chat:$id')) (groups[chat] ??= []).add(message);
        }
        yield {
          for (final entry in groups.entries)
            entry.key: List.unmodifiable(entry.value),
        };
        final next = response['next_offset'];
        offset = next is String ? next : '';
        if (offset.isNotEmpty && !offsets.add(offset)) {
          throw const FormatException(
            'Telegram search returned a repeated offset',
          );
        }
      } while (offset.isNotEmpty);
    }
  }
}
