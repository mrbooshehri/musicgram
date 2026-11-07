import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/telegram_library_sheet.dart';

void main() {
  testWidgets(
    'restoring a session shows a skeleton and sign-in has an actionable fallback',
    (tester) async {
      final status = ValueNotifier<TelegramSheetStatus>((
        state: 'initializing',
        error: null,
      ));
      addTearDown(status.dispose);
      var settingsOpened = false;
      var localOpened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 600,
              child: TelegramLibrarySheet(
                status: status,
                onPlay: (_, _, _) async {},
                onDownload: (_, _) async {},
                onDownloadPlaylist: (_, _) {},
                onOpenLocal: () => localOpened = true,
                onOpenTelegramSettings: () => settingsOpened = true,
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('libraryLoadingSkeleton')), findsOneWidget);
      expect(find.text('Telegram settings'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.tap(find.text('Local'));
      expect(localOpened, isTrue);
      status.value = (state: 'phone', error: null);
      await tester.pump();
      expect(find.byKey(const Key('libraryLoadingSkeleton')), findsNothing);
      expect(
        find.text('Sign in to Telegram to see your music.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Telegram settings'));
      expect(settingsOpened, isTrue);
    },
  );
}
