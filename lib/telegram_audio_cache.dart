import 'telegram_music_library.dart';

class TelegramChatCacheUsage {
  const TelegramChatCacheUsage(this.chatId, this.bytes);
  final int chatId;
  final int bytes;
}

/// Manages TDLib's temporary audio and document files for the active account.
class TelegramAudioCache {
  TelegramAudioCache(this.request);
  final TelegramRequest request;

  static const _types = {'fileTypeAudio', 'fileTypeDocument'};

  Future<int> size() async {
    final result = await request({
      '@type': 'getStorageStatistics',
      'chat_limit': 0,
    });
    if (result['@type'] != 'storageStatistics' || result['by_chat'] is! List) {
      throw StateError('Telegram storage statistics unavailable.');
    }
    var total = 0;
    for (final chat in result['by_chat'] as List) {
      if (chat is! Map || chat['by_file_type'] is! List) continue;
      for (final item in chat['by_file_type'] as List) {
        if (item is! Map || item['file_type'] is! Map) continue;
        if (_types.contains((item['file_type'] as Map)['@type']) &&
            item['size'] is int) {
          total += item['size'] as int;
        }
      }
    }
    return total;
  }

  Future<List<TelegramChatCacheUsage>> byChat() async {
    final result = await request({
      '@type': 'getStorageStatistics',
      'chat_limit': 100000,
    });
    if (result['@type'] != 'storageStatistics' || result['by_chat'] is! List) {
      throw StateError('Telegram storage statistics unavailable.');
    }
    final chats = <TelegramChatCacheUsage>[];
    for (final chat in result['by_chat'] as List) {
      if (chat is! Map ||
          chat['chat_id'] is! int ||
          chat['by_file_type'] is! List) {
        continue;
      }
      var bytes = 0;
      for (final item in chat['by_file_type'] as List) {
        if (item is Map &&
            item['file_type'] is Map &&
            _types.contains((item['file_type'] as Map)['@type']) &&
            item['size'] is int) {
          bytes += item['size'] as int;
        }
      }
      if (bytes > 0) {
        chats.add(TelegramChatCacheUsage(chat['chat_id'] as int, bytes));
      }
    }
    chats.sort((a, b) => b.bytes.compareTo(a.bytes));
    return chats;
  }

  Future<int> clearChat(int chatId) {
    if (chatId == 0) {
      throw ArgumentError('The aggregated group is not a single chat.');
    }
    return _clear([chatId]);
  }

  Future<int> clear() => _clear([]);

  Future<int> _clear(List<int> chatIds) async {
    final result = await request({
      '@type': 'optimizeStorage',
      'size': 0,
      'ttl': -1,
      'count': -1,
      'immunity_delay': 0,
      'file_types': [
        for (final type in _types) {'@type': type},
      ],
      'chat_ids': chatIds,
      'exclude_chat_ids': <int>[],
      'return_deleted_file_statistics': true,
      'chat_limit': 0,
    });
    if (result['@type'] != 'storageStatistics' || result['size'] is! int) {
      throw StateError('Telegram cache cleanup failed.');
    }
    return result['size'] as int;
  }
}
