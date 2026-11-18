import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/gogh_presets.dart';
import 'package:musicgram/main.dart';

void main() {
  test('all Gogh presets are selectable with readable text', () {
    expect(goghPresets.length, 48);
    for (final entry in goghPresets.entries) {
      expect(AppPalette.values.any((value) => value.name == entry.key), isTrue);
      final (dark, darkSurface, darkText, _, light, lightSurface, lightText) =
          goghThemeColors(entry.value);
      for (final pair in [
        (dark, darkText),
        (darkSurface, darkText),
        (light, lightText),
        (lightSurface, lightText),
      ]) {
        final a = pair.$1.computeLuminance();
        final b = pair.$2.computeLuminance();
        expect(
          (math.max(a, b) + .05) / (math.min(a, b) + .05),
          greaterThanOrEqualTo(4.5),
          reason: entry.value.name,
        );
      }
    }
  });
}
