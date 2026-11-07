import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'telegram_music_library.dart';

/// Selected Telegram chats are stored separately for each verified account.
class TelegramSyncSelection {
  TelegramSyncSelection({required this.request, this.directory});
  final TelegramRequest request;
  final Future<Directory> Function()? directory;

  Future<File> _file() async {
    final user = await request({'@type': 'getMe'});
    final id = user['id'];
    if (id is! int || id <= 0) {
      throw const FormatException('Invalid Telegram account');
    }
    final root = await (directory?.call() ?? getApplicationSupportDirectory());
    return File('${root.path}/telegram_sync_selection_$id.json');
  }

  Future<Set<int>> load() async {
    final file = await _file();
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is! List || data.any((id) => id is! int || id == 0)) {
        throw const FormatException('Invalid Telegram chat selection');
      }
      return data.cast<int>().toSet();
    } on PathNotFoundException {
      return {};
    }
  }

  Future<void> save(Set<int> selected) async {
    if (selected.contains(0)) throw ArgumentError('Invalid Telegram chat ID');
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(selected.toList()), flush: true);
    await temporary.rename(file.path);
  }
}
