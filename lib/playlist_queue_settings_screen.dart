import 'package:flutter/material.dart';

import 'app_snack_bar.dart';

import 'queue_shortcut_settings.dart';

class PlaylistQueueSettingsScreen extends StatefulWidget {
  const PlaylistQueueSettingsScreen({
    super.key,
    required this.openPlaylists,
    required this.localPlaylistsAvailable,
  });
  final VoidCallback openPlaylists;
  final bool localPlaylistsAvailable;

  @override
  State<PlaylistQueueSettingsScreen> createState() =>
      _PlaylistQueueSettingsScreenState();
}

class _PlaylistQueueSettingsScreenState
    extends State<PlaylistQueueSettingsScreen> {
  bool saving = false;

  Future<void> _changeView(String value) async {
    setState(() => saving = true);
    try {
      await QueueShortcutSettings.saveOpeningView(value);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            kind: AppNoticeKind.error,
            content: Text('Could not save the opening view.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Playlists & queue')),

    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        Text('Library', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                title: const Text('Manage playlists'),
                subtitle: const Text('Create and edit playlists'),
                trailing: const Icon(Icons.chevron_right),
                onTap: widget.openPlaylists,
              ),
              ListTile(
                title: const Text('Queue shortcuts'),
                subtitle: const Text('Reorder shortcuts in the queue'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const QueueShortcutSettingsScreen(),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.localPlaylistsAvailable) ...[
          const SizedBox(height: 24),
          Text('Next up opens', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Choose what appears when you tap Next up.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<String>(
            valueListenable: QueueShortcutSettings.openingView,
            builder: (context, value, _) => Card(
              child: RadioGroup<String>(
                groupValue: value,
                onChanged: (choice) {
                  if (!saving && choice != null) _changeView(choice);
                },
                child: const Column(
                  children: [
                    RadioListTile<String>(
                      value: 'queue',
                      title: Text('Current queue'),
                    ),
                    RadioListTile<String>(
                      value: 'playlists',
                      title: Text('Local playlists'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
