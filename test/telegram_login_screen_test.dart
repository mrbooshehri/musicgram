import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/telegram_screen.dart';

void main() {
  testWidgets(
    'sign in opens a separate login screen and keeps proxy settings accessible',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: TelegramScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Proxy settings'), findsOneWidget);
      await tester.tap(find.text('Sign in'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Connecting to Telegram'), findsOneWidget);
      expect(find.text('Telegram account'), findsNothing);
      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Proxy settings'), findsOneWidget);
    },
  );
}
