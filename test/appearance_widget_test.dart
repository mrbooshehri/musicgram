import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/main.dart';

void main() {
  testWidgets('custom dark and light roles apply independently', (
    tester,
  ) async {
    addTearDown(() {
      customThemeColors.value = {};
      customAccent.value = null;
      appThemeMode.value = ThemeMode.dark;
      appPalette.value = AppPalette.gram;
    });
    customThemeColors.value = {
      'dark.background': 0xff112233,
      'dark.text': 0xffeaeaea,
      'dark.accent': 0xffffcc00,
      'light.surface': 0xffeeeecc,
      'light.text': 0xff223344,
    };
    await tester.pumpWidget(
      MusicGramApp(settings: HandPreferenceStore(), initialLeftHanded: false),
    );
    var app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.darkTheme!.scaffoldBackgroundColor, const Color(0xff112233));
    expect(app.darkTheme!.colorScheme.onSurface, const Color(0xffeaeaea));
    expect(app.darkTheme!.colorScheme.primary, const Color(0xffffcc00));
    expect(app.theme!.colorScheme.surface, const Color(0xffeeeecc));
    expect(app.theme!.colorScheme.onSurface, const Color(0xff223344));
    appPalette.value = AppPalette.catppuccin;
    await tester.pump();
    app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.darkTheme!.scaffoldBackgroundColor, const Color(0xff112233));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('appearance editor applies a custom background', (tester) async {
    appThemeMode.value = ThemeMode.dark;
    appPalette.value = AppPalette.gram;
    customThemeColors.value = {};
    addTearDown(() {
      customThemeColors.value = {};
      customAccent.value = null;
      appThemeMode.value = ThemeMode.dark;
      appPalette.value = AppPalette.gram;
    });
    await tester.pumpWidget(
      MusicGramApp(settings: HandPreferenceStore(), initialLeftHanded: false),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('settingsButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Background'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Background'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(customThemeColors.value['dark.background'], 0xff123456);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.darkTheme!.scaffoldBackgroundColor, const Color(0xff123456));
    expect(app.theme!.scaffoldBackgroundColor, Colors.white);
    await tester.pumpWidget(const SizedBox());
  });
}
