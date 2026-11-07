import 'package:flutter/foundation.dart';

import 'log_timestamp.dart';

/// Session-only summaries of errors shown to the user.
class AppDiagnostics {
  static final ValueNotifier<List<String>> entries = ValueNotifier(const []);

  static void recordError(String message) {
    var summary = message.split('\n').first.split(':').first.trim();
    if (summary.startsWith('Could not play ')) {
      summary = 'Could not play selected track';
    }
    if (summary.isEmpty) summary = 'An error occurred';
    final all = [...entries.value, '${logTimestamp(DateTime.now())}  $summary'];
    entries.value = List.unmodifiable(
      all.length > 200 ? all.sublist(all.length - 200) : all,
    );
  }
}
