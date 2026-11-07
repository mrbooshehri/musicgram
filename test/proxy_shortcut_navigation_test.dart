import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/telegram_screen.dart';

void main() {
  testWidgets('proxy shortcut back returns to player', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const TelegramScreen(openProxyList: true),
                ),
              ),
              child: const Text('Player'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Player'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Proxy settings'), findsWidgets);
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Player'), findsOneWidget);
  });
}
