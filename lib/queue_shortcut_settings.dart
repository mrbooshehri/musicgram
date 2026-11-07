import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_snack_bar.dart';

import 'package:path_provider/path_provider.dart';

class QueueShortcutSettings {
  static const defaults = [
    'All songs',
    'Artists',
    'Albums',
    'Genres',
    'Playlists',
  ];
  static final order = ValueNotifier<List<String>>(List.of(defaults));
  static final openingView = ValueNotifier<String>('queue');
  static Future<File> _file() async => File(
    '${(await getApplicationSupportDirectory()).path}/queue_shortcuts.json',
  );
  static Future<void> load() async {
    try {
      final data = jsonDecode(await (await _file()).readAsString());
      final items = (data is List ? data : [])
          .whereType<String>()
          .where(defaults.contains)
          .toSet()
          .toList();
      for (final item in defaults) {
        if (!items.contains(item)) items.add(item);
      }
      order.value = items;
    } catch (_) {
      /* Use defaults if no valid saved order exists. */
    }
    try {
      final data = jsonDecode(await (await _viewFile()).readAsString());
      openingView.value = data == 'playlists' ? 'playlists' : 'queue';
    } catch (_) {
      openingView.value = 'queue';
    }
  }

  static Future<File> _viewFile() async => File(
    '${(await getApplicationSupportDirectory()).path}/queue_opening_view.json',
  );

  static Future<void> saveOpeningView(String value) async {
    if (value != 'queue' && value != 'playlists') {
      throw ArgumentError.value(value, 'value');
    }
    final file = await _viewFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(value), flush: true);
    openingView.value = value;
  }

  static Future<void> save(List<String> items) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(items), flush: true);
    order.value = List.unmodifiable(items);
  }
}

class QueueShortcutSettingsScreen extends StatefulWidget {
  const QueueShortcutSettingsScreen({super.key});
  @override
  State<QueueShortcutSettingsScreen> createState() =>
      _QueueShortcutSettingsScreenState();
}

class _QueueShortcutSettingsScreenState
    extends State<QueueShortcutSettingsScreen> {
  late final List<String> items = List.of(QueueShortcutSettings.order.value);
  bool saving = false;
  Future<void> save() async {
    setState(() => saving = true);
    try {
      await QueueShortcutSettings.save(items);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            kind: AppNoticeKind.error,
            content: Text('Could not save shortcut order.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Queue shortcuts'),
      actions: [
        TextButton(
          onPressed: saving
              ? null
              : () => setState(() {
                  items
                    ..clear()
                    ..addAll(QueueShortcutSettings.defaults);
                }),
          child: const Text('Reset'),
        ),
        TextButton(onPressed: saving ? null : save, child: const Text('Save')),
      ],
    ),
    body: ReorderableListView(
      onReorderItem: (oldIndex, newIndex) => setState(() {
        items.insert(newIndex, items.removeAt(oldIndex));
      }),
      children: [
        for (final item in items)
          Card(
            key: ValueKey(item),
            child: ListTile(
              title: Text(item),
              leading: const Icon(Icons.drag_handle),
            ),
          ),
      ],
    ),
  );
}
