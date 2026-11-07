import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/music_storage.dart';
import 'package:musicgram/music_storage_screen.dart';

void main() {
  testWidgets('folder details display size and track count', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MusicStorageScreen(
          title: 'Local music',
          folders: [FolderUsage('/Music/Album', 2048, 2)],
        ),
      ),
    );
    expect(find.text('Local music'), findsOneWidget);
    expect(find.text('/Music/Album'), findsOneWidget);
    expect(find.text('2 tracks'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
  });
}
