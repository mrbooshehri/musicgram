import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:musicgram/download_settings.dart';

void main() {
  test('folder names cannot escape the Music directory', () {
    expect(DownloadSettings.validFolder('My music'), isTrue);
    for (final name in [
      '',
      ' ',
      '.',
      '..',
      '../other',
      'bad/name',
      r'bad\name',
    ]) {
      expect(DownloadSettings.validFolder(name), isFalse, reason: name);
    }
  });
  test('new downloads use MusicGram while existing folder preferences remain intact', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'read'
          ? '{"folder":"MusicGram","concurrency":2}'
          : null,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final settings = DownloadSettings();
    expect(settings.folder, 'MusicGram');
    await settings.load();
    expect(settings.folder, 'MusicGram');
    expect(settings.concurrency, 2);
  });
}
