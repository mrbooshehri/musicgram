import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_snack_bar.dart';
import 'telegram_playback_log.dart';
import 'playback_diagnostics.dart';
import 'telegram_connection_log.dart';
import 'app_diagnostics.dart';

class DiagnosticsLogsScreen extends StatelessWidget {
  const DiagnosticsLogsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Logs')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Logs are kept for this app session.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        _section(
          context,
          'Telegram connection',
          Icons.cloud_outlined,
          telegramConnectionLog,
        ),
        _section(
          context,
          'Telegram playback',
          Icons.play_circle_outline,
          TelegramPlaybackLog.entries,
        ),
        _section(
          context,
          'Player errors',
          Icons.error_outline,
          PlaybackDiagnostics.entries,
        ),
        _section(
          context,
          'Application errors',
          Icons.warning_amber_outlined,
          AppDiagnostics.entries,
        ),
      ],
    ),
  );

  Widget _section(
    BuildContext context,
    String title,
    IconData icon,
    ValueNotifier<List<String>> log,
  ) => ValueListenableBuilder<List<String>>(
    valueListenable: log,
    builder: (context, entries, _) => Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text('${entries.length} events'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _LogPage(title: title, log: log),
          ),
        ),
      ),
    ),
  );
}

class _LogPage extends StatefulWidget {
  const _LogPage({required this.title, required this.log});
  final String title;
  final ValueNotifier<List<String>> log;

  @override
  State<_LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<_LogPage> {
  final scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.log.addListener(_followLatest);
  }

  void _followLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) scroll.jumpTo(0);
    });
  }

  @override
  void dispose() {
    widget.log.removeListener(_followLatest);
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: SafeArea(
      child: ValueListenableBuilder<List<String>>(
        valueListenable: widget.log,
        builder: (context, entries, _) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${entries.length} events',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  TextButton.icon(
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
                                  content: const Text('Log copied.'),
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy'),
                  ),
                  TextButton.icon(
                    onPressed: entries.isEmpty
                        ? null
                        : () => widget.log.value = const [],
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Clear'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? const Center(child: Text('No events yet.'))
                  : ListView.builder(
                      controller: scroll,
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: entries.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: SelectableText(
                          entries[entries.length - 1 - index],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
