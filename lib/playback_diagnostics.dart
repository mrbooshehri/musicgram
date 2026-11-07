import 'package:flutter/foundation.dart';

import 'log_timestamp.dart';

class PlaybackDiagnostics {
  static final ValueNotifier<List<String>> entries = ValueNotifier(const []);
  static void record(String event) {
    final now = logTimestamp(DateTime.now());
    final all = [...entries.value, '$now  $event'];
    entries.value = List.unmodifiable(
      all.length > 200 ? all.sublist(all.length - 200) : all,
    );
  }
}
