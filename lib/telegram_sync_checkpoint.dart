import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Pending chat IDs for a verified session, stored independently per account.
class TelegramSyncCheckpoint {
  TelegramSyncCheckpoint({this.directory});
  final Future<Directory> Function()? directory;

  Future<File> _file(String session) async {
    if (session != 'legacy' &&
        !RegExp(r'^session_[a-zA-Z0-9_-]{1,64}$').hasMatch(session)) {
      throw ArgumentError.value(session, 'session');
    }
    final root = await (directory?.call() ?? getApplicationSupportDirectory());
    return File('${root.path}/telegram_sync_$session.json');
  }

  Future<Set<int>?> load(String session) async {
    final file = await _file(session);
    try {
      final value = jsonDecode(await file.readAsString());
      if (value is! Map || value['version'] != 1 || value['pending'] is! List) {
        throw const FormatException('Invalid Telegram sync checkpoint');
      }
      final pending = value['pending'] as List;
      if (pending.any((item) => item is! int || item == 0)) {
        throw const FormatException('Invalid Telegram sync chat IDs');
      }
      return pending.cast<int>().toSet();
    } on PathNotFoundException {
      return null;
    }
  }

  Future<bool> isCancelled(String session) async =>
      File('${(await _file(session)).path}.cancelled').exists();

  Future<void> clearCancellation(String session) async {
    final marker = File('${(await _file(session)).path}.cancelled');
    try {
      await marker.delete();
    } on PathNotFoundException {
      // No cancellation marker exists.
    }
  }

  Future<void> save(String session, Set<int> pending) async {
    if (pending.contains(0)) throw ArgumentError('Invalid chat ID');
    final file = await _file(session);
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({'version': 1, 'pending': pending.toList()}),
      flush: true,
    );
    await tmp.rename(file.path);
  }

  Future<void> clear(String session) async {
    try {
      await (await _file(session)).delete();
    } on PathNotFoundException {
      // Already cleared.
    }
  }
}
