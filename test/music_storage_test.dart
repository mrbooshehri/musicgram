import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/music_storage.dart';

void main() {
  test('groups tracks by folder, sorts by size, and separates sources', () {
    final summary = MusicStorageSummary.fromMap({
      'capacity': 1000,
      'free': 200,
      'files': [
        {'folder': 'Music/A', 'bytes': 100, 'telegram': false},
        {'folder': 'Music/A', 'bytes': 50, 'telegram': false},
        {'folder': 'Music/B', 'bytes': 200, 'telegram': false},
        {'folder': 'Music/Telegram/Chat', 'bytes': 300, 'telegram': true},
      ],
    });
    expect(summary.local.map((e) => e.bytes), [200, 150]);
    expect(summary.localBytes, 350);
    expect(summary.telegramBytes, 300);
    expect(summary.usedBytes, 800);
  });
}
