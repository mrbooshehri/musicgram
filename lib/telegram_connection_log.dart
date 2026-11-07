import 'package:flutter/foundation.dart';

import 'log_timestamp.dart';

final ValueNotifier<List<String>> telegramConnectionLog = ValueNotifier(
  const [],
);

void recordTelegramConnection(String event) {
  final entries = [
    ...telegramConnectionLog.value,
    '${logTimestamp(DateTime.now())}  $event',
  ];
  telegramConnectionLog.value = List.unmodifiable(
    entries.length > 100 ? entries.sublist(entries.length - 100) : entries,
  );
}
