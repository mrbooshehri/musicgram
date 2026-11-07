import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class AppearanceSettings {
  const AppearanceSettings({
    this.mode = 'dark',
    this.palette = 'gram',
    this.accent,
    this.colors = const {},
  });
  final String mode;
  final String palette;
  final int? accent;
  final Map<String, int> colors;

  factory AppearanceSettings.fromJson(Map<String, dynamic> data) =>
      AppearanceSettings(
        mode: const ['dark', 'light', 'system'].contains(data['mode'])
            ? data['mode'] as String
            : 'dark',
        palette:
            const [
              'gram',
              'dracula',
              'gruvbox',
              'nord',
              'catppuccin',
              'tokyo',
              'solarized',
              'oneDark',
            ].contains(data['palette'])
            ? data['palette'] as String
            : 'gram',
        accent:
            data['accent'] is int &&
                (data['accent'] as int) >= 0 &&
                (data['accent'] as int) <= 0xffffffff
            ? data['accent'] as int
            : null,
        colors: data['colors'] is Map
            ? {
                for (final entry in (data['colors'] as Map).entries)
                  if (const {
                        'dark.background',
                        'dark.surface',
                        'dark.text',
                        'dark.accent',
                        'light.background',
                        'light.surface',
                        'light.text',
                        'light.accent',
                      }.contains(entry.key) &&
                      entry.value is int &&
                      entry.value >= 0 &&
                      entry.value <= 0xffffffff)
                    entry.key as String: entry.value as int,
              }
            : const {},
      );
  Map<String, dynamic> toJson() => {
    'mode': mode,
    'palette': palette,
    'accent': accent,
    'colors': colors,
  };
}

class AppearanceSettingsStore {
  AppearanceSettingsStore({this.directory});
  final Future<Directory> Function()? directory;
  Future<void> _writes = Future.value();
  Future<File> _file() async => File(
    '${(await (directory?.call() ?? getApplicationSupportDirectory())).path}/appearance_settings.json',
  );

  Future<AppearanceSettings> load() async {
    try {
      final data = jsonDecode(await (await _file()).readAsString());
      return data is Map<String, dynamic>
          ? AppearanceSettings.fromJson(data)
          : const AppearanceSettings();
    } on FileSystemException catch (_) {
      return const AppearanceSettings();
    } on FormatException catch (_) {
      return const AppearanceSettings();
    }
  }

  Future<void> save(AppearanceSettings settings) {
    final next = _writes.then((_) async {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(settings.toJson()), flush: true);
    });
    _writes = next.catchError((_) {});
    return next;
  }
}
