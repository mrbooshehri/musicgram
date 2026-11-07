import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/about_diagnostics_screen.dart';

void main() {
  testWidgets('displays version and retains access to open-source notices', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AboutDiagnosticsScreen(version: () async => '1.2.3 (4)'),
      ),
    );
    await tester.pump();
    expect(find.text('MusicGram'), findsOneWidget);
    expect(find.byKey(const Key('aboutAppLogo')), findsOneWidget);
    expect(find.text('Version 1.2.3 (4)'), findsOneWidget);
    expect(find.text('Open-source licenses'), findsOneWidget);
    expect(find.text('Copy app details'), findsOneWidget);
    await tester.tap(find.text('Open-source licenses'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });
}
