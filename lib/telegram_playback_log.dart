import 'package:flutter/material.dart';

import 'app_snack_bar.dart';
import 'log_timestamp.dart';

import 'package:flutter/services.dart';

/// Session-only diagnostics. Callers must not include track or account data.
class TelegramPlaybackLog {
  static const int maxEntries = 300;
  static final ValueNotifier<List<String>> entries = ValueNotifier(const []);

  static void record(String event) {
    final timestamp = logTimestamp(DateTime.now());
    final all = [...entries.value, '$timestamp  $event'];
    entries.value = List.unmodifiable(
      all.length > maxEntries ? all.sublist(all.length - maxEntries) : all,
    );
  }

  static void clear() => entries.value = const [];
}

void showTelegramPlaybackLog(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: Column(
          children: [
            ListTile(
              title: const Text('Telegram playback log'),
              subtitle: const Text(
                'Session only. Track names, paths and credentials are excluded.',
              ),
              trailing: IconButton(
                tooltip: 'Clear playback log',
                icon: const Icon(Icons.delete_outline),
                onPressed: TelegramPlaybackLog.clear,
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<List<String>>(
                valueListenable: TelegramPlaybackLog.entries,
                builder: (context, entries, _) => entries.isEmpty
                    ? const Center(child: Text('No playback events yet.'))
                    : ListView.builder(
                        itemCount: entries.length,
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: SelectableText(entries[index]),
                        ),
                      ),
              ),
            ),
            ValueListenableBuilder<List<String>>(
              valueListenable: TelegramPlaybackLog.entries,
              builder: (context, entries, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: entries.isEmpty
                      ? null
                      : () async {
                          await Clipboard.setData(
                            ClipboardData(text: entries.join('\n')),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              AppSnackBar(
                                kind: AppNoticeKind.success,
                                content: Text('Playback log copied.'),
                              ),
                            );
                          }
                        },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy log'),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
