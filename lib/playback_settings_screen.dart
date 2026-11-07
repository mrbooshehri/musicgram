import 'package:flutter/material.dart';

import 'app_snack_bar.dart';

import 'playback_settings.dart';

class PlaybackSettingsScreen extends StatefulWidget {
  const PlaybackSettingsScreen({
    super.key,
    this.onSaved,
    this.loadSettings,
    this.saveSettings,
  });
  final ValueChanged<PlaybackSettings>? onSaved;
  final Future<PlaybackSettings> Function()? loadSettings;
  final Future<void> Function(PlaybackSettings)? saveSettings;

  @override
  State<PlaybackSettingsScreen> createState() => _PlaybackSettingsScreenState();
}

class _PlaybackSettingsScreenState extends State<PlaybackSettingsScreen> {
  PlaybackSettings? settings;
  bool saving = false;
  bool loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loadFailed = false);
    try {
      final value =
          await (widget.loadSettings?.call() ?? PlaybackSettings.load());
      if (mounted) setState(() => settings = value);
    } catch (_) {
      if (mounted) {
        setState(() => loadFailed = true);
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            kind: AppNoticeKind.error,
            content: Text('Could not load playback settings.'),
          ),
        );
      }
    }
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      final value = settings!;
      await (widget.saveSettings?.call(value) ?? value.save());
      widget.onSaved?.call(value);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            kind: AppNoticeKind.error,
            content: Text('Could not save playback settings.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Playback')),
      body: value == null
          ? Center(
              child: loadFailed
                  ? TextButton(
                      onPressed: _load,
                      child: const Text('Retry loading settings'),
                    )
                  : const CircularProgressIndicator(),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              children: [
                Text(
                  'On launch',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Resume playback'),
                        subtitle: const Text('Resume the last local song'),
                        value: value.resumeOnLaunch,
                        onChanged: saving
                            ? null
                            : (enabled) => setState(
                                () => value.resumeOnLaunch = enabled,
                              ),
                      ),
                      ListTile(
                        title: const Text('Repeat on launch'),
                        subtitle: Text(_defaultLabel(value.repeat)),
                        trailing: const Icon(Icons.chevron_right),
                        enabled: !saving,
                        onTap: () async {
                          final result = await _choose<PlaybackDefault>(
                            'Repeat on launch',
                            value.repeat,
                            {
                              for (final item in PlaybackDefault.values)
                                item: _defaultLabel(item),
                            },
                          );
                          if (mounted && result != null) {
                            setState(() => value.repeat = result);
                          }
                        },
                      ),
                      ListTile(
                        title: const Text('Shuffle on launch'),
                        subtitle: Text(_defaultLabel(value.shuffle)),
                        trailing: const Icon(Icons.chevron_right),
                        enabled: !saving,
                        onTap: () async {
                          final result = await _choose<PlaybackDefault>(
                            'Shuffle on launch',
                            value.shuffle,
                            {
                              for (final item in PlaybackDefault.values)
                                item: _defaultLabel(item),
                            },
                          );
                          if (mounted && result != null) {
                            setState(() => value.shuffle = result);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Player controls',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Swipe artwork to change tracks'),
                        value: value.artworkSwipe,
                        onChanged: saving
                            ? null
                            : (enabled) =>
                                  setState(() => value.artworkSwipe = enabled),
                      ),
                      ListTile(
                        title: const Text('Previous button'),
                        subtitle: Text(
                          _previousLabels[value.previousRestartSeconds]!,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        enabled: !saving,
                        onTap: () async {
                          final result = await _choose<int>(
                            'Previous button',
                            value.previousRestartSeconds,
                            _previousLabels,
                          );
                          if (mounted && result != null) {
                            setState(
                              () => value.previousRestartSeconds = result,
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: saving ? null : _save,
                  child: Text(saving ? 'Saving…' : 'Save changes'),
                ),
              ],
            ),
    );
  }

  static const _previousLabels = <int, String>{
    0: 'Always skip to previous',
    3: 'Restart after 3 seconds',
    5: 'Restart after 5 seconds',
    10: 'Restart after 10 seconds',
  };

  String _defaultLabel(PlaybackDefault value) => switch (value) {
    PlaybackDefault.remember => 'Remember last setting',
    PlaybackDefault.on => 'On',
    PlaybackDefault.off => 'Off',
  };

  Future<T?> _choose<T>(String title, T selected, Map<T, String> options) =>
      showModalBottomSheet<T>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              for (final entry in options.entries)
                ListTile(
                  title: Text(entry.value),
                  trailing: entry.key == selected
                      ? Icon(
                          Icons.check,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.pop(context, entry.key),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      );
}
