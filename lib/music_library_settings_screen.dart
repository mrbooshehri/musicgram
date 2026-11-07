import 'package:flutter/material.dart';

import 'app_snack_bar.dart';

import 'package:file_picker/file_picker.dart';

import 'music_library_settings.dart';

class MusicLibrarySettingsScreen extends StatefulWidget {
  const MusicLibrarySettingsScreen({super.key, this.onSaved});
  final VoidCallback? onSaved;
  @override
  State<MusicLibrarySettingsScreen> createState() =>
      _MusicLibrarySettingsScreenState();
}

class _MusicLibrarySettingsScreenState
    extends State<MusicLibrarySettingsScreen> {
  bool loading = true;
  bool saving = false;
  String? error;
  List<Map<String, dynamic>> songs = [];
  int minimum = 0;
  Set<String> excluded = {};
  bool excludeWhatsApp = true;
  bool excludeTelegram = false;
  bool excludeMessenger = false;
  bool includeUnknownDuration = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await MusicLibrarySettings.load();
      if (!mounted) return;
      setState(() {
        minimum = settings.minimumSeconds;
        excluded = settings.excludedFolders.toSet();
        excludeWhatsApp = settings.excludeWhatsApp;
        excludeTelegram = settings.excludeTelegram;
        excludeMessenger = settings.excludeMessenger;
        includeUnknownDuration = settings.includeUnknownDuration;
      });
      await _scan();
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Could not load library settings.';
        });
      }
    }
  }

  MusicLibrarySettings _currentSettings() => MusicLibrarySettings(
    minimumSeconds: minimum,
    excludedFolders: excluded.toList(),
    excludeWhatsApp: excludeWhatsApp,
    excludeTelegram: excludeTelegram,
    excludeMessenger: excludeMessenger,
    includeUnknownDuration: includeUnknownDuration,
  );

  Future<void> _scan({bool apply = false}) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (apply) await _currentSettings().save();
      final found = await scanMusicLibrary(filtered: false);
      if (mounted) {
        setState(() => songs = found);
        if (apply) widget.onSaved?.call();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not scan music. Check your music permission and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await _currentSettings().save();
      if (mounted) {
        widget.onSaved?.call();
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            kind: AppNoticeKind.error,
            content: Text('Could not save library settings.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _addFolder(String value) {
    final folder = value.trim().replaceFirst(RegExp(r'/+$'), '');
    if (!folder.startsWith('/') || folder.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        AppSnackBar(
          kind: AppNoticeKind.info,
          content: Text(
            'Enter an absolute folder path, such as /storage/emulated/0/Music/Voice.',
          ),
        ),
      );
      return;
    }
    if (excluded.contains(folder)) {
      ScaffoldMessenger.of(context).showSnackBar(
        AppSnackBar(
          kind: AppNoticeKind.warning,
          content: Text('This folder is already excluded.'),
        ),
      );
      return;
    }
    setState(() => excluded.add(folder));
  }

  Future<void> _chooseFolder() async {
    try {
      final folder = await FilePicker.getDirectoryPath(
        dialogTitle: 'Choose a folder to exclude',
      );
      if (mounted && folder != null) _addFolder(folder);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            kind: AppNoticeKind.error,
            content: Text(
              'Could not choose this folder. Try entering its path instead.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _enterFolder() async {
    var entered = '';
    final folder = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter folder path'),
        content: TextField(
          autofocus: true,
          onChanged: (value) => entered = value,
          decoration: const InputDecoration(
            labelText: 'Absolute folder path',
            hintText: '/storage/emulated/0/Music/Voice',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, entered),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (mounted && folder != null) _addFolder(folder);
  }

  @override
  Widget build(BuildContext context) {
    final sorted = excluded.toList()..sort();
    final draft = MusicLibrarySettings(
      minimumSeconds: minimum,
      excludedFolders: sorted,
      excludeWhatsApp: excludeWhatsApp,
      excludeTelegram: excludeTelegram,
      excludeMessenger: excludeMessenger,
      includeUnknownDuration: includeUnknownDuration,
    );
    final matching = songs.where(draft.matches).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Music library')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          Text('Local music', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              title: const Text('Rescan local music'),
              subtitle: Text(
                loading
                    ? 'Scanning…'
                    : error ??
                          '$matching of ${songs.length} tracks match these settings',
              ),
              trailing: loading
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              onTap: loading || saving ? null : () => _scan(apply: true),
            ),
          ),
          const SizedBox(height: 24),
          Text('Track filters', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: DropdownButtonFormField<int>(
                    initialValue: [0, 15, 30, 60, 120].contains(minimum)
                        ? minimum
                        : 0,
                    decoration: const InputDecoration(
                      labelText: 'Minimum track length',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('No minimum')),
                      DropdownMenuItem(value: 15, child: Text('15 seconds')),
                      DropdownMenuItem(value: 30, child: Text('30 seconds')),
                      DropdownMenuItem(value: 60, child: Text('1 minute')),
                      DropdownMenuItem(value: 120, child: Text('2 minutes')),
                    ],
                    onChanged: saving
                        ? null
                        : (value) => setState(() => minimum = value ?? 0),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Include tracks with unknown duration'),
                  value: includeUnknownDuration,
                  onChanged: saving
                      ? null
                      : (value) =>
                            setState(() => includeUnknownDuration = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Exclude app audio',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Exclude WhatsApp audio'),
                  subtitle: const Text(
                    'Includes WhatsApp Business and voice notes',
                  ),
                  value: excludeWhatsApp,
                  onChanged: saving
                      ? null
                      : (value) => setState(() => excludeWhatsApp = value),
                ),
                SwitchListTile(
                  title: const Text('Exclude Telegram audio'),
                  subtitle: const Text(
                    'Local Telegram Audio and Voice folders',
                  ),
                  value: excludeTelegram,
                  onChanged: saving
                      ? null
                      : (value) => setState(() => excludeTelegram = value),
                ),
                SwitchListTile(
                  title: const Text('Exclude Messenger audio'),
                  value: excludeMessenger,
                  onChanged: saving
                      ? null
                      : (value) => setState(() => excludeMessenger = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Excluded folders',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text(
            'Folders and their subfolders are hidden from the library.',
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                if (sorted.isEmpty)
                  const ListTile(title: Text('No folders excluded.')),
                for (final folder in sorted)
                  ListTile(
                    title: Text(
                      folder,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    trailing: IconButton(
                      tooltip: 'Remove excluded folder',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: saving
                          ? null
                          : () => setState(() => excluded.remove(folder)),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: saving ? null : _chooseFolder,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Choose folder'),
                      ),
                      OutlinedButton.icon(
                        onPressed: saving ? null : _enterFolder,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Enter path'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: saving ? null : _save,
            child: Text(saving ? 'Saving…' : 'Save'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Rescan or save to apply filters. The current track keeps playing.',
          ),
        ],
      ),
    );
  }
}
