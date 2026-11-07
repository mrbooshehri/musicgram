import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/app_snack_bar.dart';
import 'package:musicgram/app_diagnostics.dart';

void main() {
  test('error toast writes a safe summary to application logs', () {
    AppDiagnostics.entries.value = [];
    addTearDown(() => AppDiagnostics.entries.value = []);
    AppSnackBar(
      kind: AppNoticeKind.error,
      content: const Text('Download failed: private details'),
    );
    expect(AppDiagnostics.entries.value.single, contains('Download failed'));
    expect(
      AppDiagnostics.entries.value.single,
      isNot(contains('private details')),
    );
  });
  for (final entry in {
    AppNoticeKind.info: Icons.info_outline,
    AppNoticeKind.success: Icons.check_circle_outline,
    AppNoticeKind.warning: Icons.warning_amber_rounded,
    AppNoticeKind.error: Icons.error_outline,
  }.entries) {
    testWidgets(
      '${entry.key.name} feedback uses the common floating style and icon',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    AppSnackBar(
                      content: const Text('Message'),
                      kind: entry.key,
                    ),
                  ),
                  child: const Text('Show'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Show'));
        await tester.pumpAndSettle();
        expect(find.text('Message'), findsOneWidget);
        expect(find.byIcon(entry.value), findsOneWidget);
        expect(
          tester.widget<SnackBar>(find.byType(SnackBar)).behavior,
          SnackBarBehavior.floating,
        );
        expect(
          tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
          switch (entry.key) {
            AppNoticeKind.info => const Color(0xFF155A96),
            AppNoticeKind.success => const Color(0xFF226B35),
            AppNoticeKind.warning => const Color(0xFF805500),
            AppNoticeKind.error => const Color(0xFFAE2424),
          },
        );
      },
    );
  }
}
