import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/appearance_settings.dart';

void main() {
  test('appearance choices persist and invalid values fall back', () async {
    final dir = await Directory.systemTemp.createTemp('musicgram_appearance');
    addTearDown(() => dir.delete(recursive: true));
    final store = AppearanceSettingsStore(directory: () async => dir);
    await Future.wait([
      store.save(
        const AppearanceSettings(
          mode: 'light',
          palette: 'nord',
          accent: 0xff112233,
        ),
      ),
      store.save(
        const AppearanceSettings(
          mode: 'system',
          palette: 'dracula',
          accent: 0xffabcdef,
        ),
      ),
    ]);
    final loaded = await store.load();
    expect(loaded.mode, 'system');
    expect(loaded.palette, 'dracula');
    expect(loaded.accent, 0xffabcdef);
    final fallback = AppearanceSettings.fromJson({
      'mode': 'bad',
      'palette': 'bad',
      'accent': -1,
    });
    expect(fallback.mode, 'dark');
    expect(fallback.palette, 'gram');
    expect(fallback.accent, isNull);
  });
  test('persists custom role colors and accepts new presets', () async {
    final dir = await Directory.systemTemp.createTemp('appearance_roles');
    addTearDown(() => dir.delete(recursive: true));
    final store = AppearanceSettingsStore(directory: () async => dir);
    await store.save(
      const AppearanceSettings(
        palette: 'catppuccin',
        colors: {'dark.background': 0xff112233, 'light.text': 0xff445566},
      ),
    );
    final loaded = await store.load();
    expect(loaded.palette, 'catppuccin');
    expect(loaded.colors['dark.background'], 0xff112233);
    expect(loaded.colors['light.text'], 0xff445566);
    final invalid = AppearanceSettings.fromJson({
      'colors': {
        'dark.background': -1,
        'unknown': 0xff000000,
        'light.text': 'bad',
      },
    });
    expect(invalid.colors, isEmpty);
  });
}
