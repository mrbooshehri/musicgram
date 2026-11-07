import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/music_library_settings.dart';

void main() {
  test(
    'excludes selected folders and checks duration and folder boundaries',
    () {
      final settings = MusicLibrarySettings(
        excludedFolders: ['/storage/Music/Noise'],
        minimumSeconds: 30,
      );
      expect(
        settings.matches({
          'path': '/storage/Music/Album/song.mp3',
          'duration': '30000',
        }),
        isTrue,
      );
      expect(
        settings.matches({
          'path': '/storage/Music/song.mp3',
          'duration': '29999',
        }),
        isFalse,
      );
      expect(settings.matches({'path': '/storage/Music/song.mp3'}), isTrue);
      expect(
        settings.matches({
          'path': '/storage/Music/Noise/sub/beep.mp3',
          'duration': '60000',
        }),
        isFalse,
      );
      expect(
        settings.matches({
          'path': '/storage/Music/Noise2/song.mp3',
          'duration': '60000',
        }),
        isTrue,
      );
    },
  );

  test('excludes WhatsApp audio and voice notes by default', () {
    final settings = MusicLibrarySettings();
    for (final path in [
      '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Audio/song.mp3',
      '/storage/emulated/0/WhatsApp/Media/WhatsApp Voice Notes/2026/voice.opus',
      '/storage/123/WhatsApp Business/Media/WhatsApp Business Voice Notes/voice.opus',
      '/storage/123/whatsapp business audio/song.mp3',
    ]) {
      expect(settings.matches({'path': path}), isFalse, reason: path);
    }
    expect(
      settings.matches({
        'path': '/storage/Music/WhatsApp Audio archive/song.mp3',
      }),
      isTrue,
    );
    expect(settings.matches({'path': '/storage/Music/song.mp3'}), isTrue);
  });

  test(
    'WhatsApp filter can be disabled without disabling explicit exclusions',
    () {
      final settings = MusicLibrarySettings(
        excludeWhatsApp: false,
        excludedFolders: ['/storage/other'],
      );
      expect(
        settings.matches({'path': '/storage/WhatsApp Audio/song.mp3'}),
        isTrue,
      );
      expect(settings.matches({'path': '/storage/other/song.mp3'}), isFalse);
      final restored = MusicLibrarySettings.fromJson(settings.toJson());
      expect(restored.excludeWhatsApp, isFalse);
      expect(restored.excludedFolders, ['/storage/other']);
    },
  );

  test('legacy settings retain exclusions and enable the WhatsApp filter', () {
    final settings = MusicLibrarySettings.fromJson({
      'minimumSeconds': 30,
      'includedFolders': ['/storage/old-include'],
      'excludedFolders': ['/storage/noise'],
    });
    expect(settings.minimumSeconds, 30);
    expect(settings.excludedFolders, ['/storage/noise']);
    expect(settings.excludeWhatsApp, isTrue);
    expect(settings.matches({'path': '/storage/new/song.mp3'}), isTrue);
    expect(
      settings.matches({'path': '/storage/WhatsApp Voice Notes/voice.opus'}),
      isFalse,
    );
    expect(settings.toJson().containsKey('includedFolders'), isFalse);
  });
  test(
    'messaging app filters are opt-in and do not match unrelated folders',
    () {
      final defaults = MusicLibrarySettings();
      final settings = MusicLibrarySettings(
        excludeTelegram: true,
        excludeMessenger: true,
      );
      const telegram = '/storage/emulated/0/Telegram/Telegram Voice/voice.ogg';
      const messenger =
          '/storage/emulated/0/Android/media/com.facebook.orca/recording.mp3';
      expect(defaults.matches({'path': telegram}), isTrue);
      expect(defaults.matches({'path': messenger}), isTrue);
      expect(settings.matches({'path': telegram}), isFalse);
      expect(
        settings.matches({
          'path': '/storage/emulated/0/Telegram/Telegram Audio/song.mp3',
        }),
        isFalse,
      );
      expect(settings.matches({'path': messenger}), isFalse);
      expect(
        settings.matches({
          'path': '/storage/Music/Telegram Audio archive/song.mp3',
        }),
        isTrue,
      );
      expect(
        settings.matches({
          'path': '/storage/Android/media/com.facebook.orca.backup/song.mp3',
        }),
        isTrue,
      );
      final restored = MusicLibrarySettings.fromJson(settings.toJson());
      expect(restored.excludeTelegram, isTrue);
      expect(restored.excludeMessenger, isTrue);
      final old = MusicLibrarySettings.fromJson({});
      expect(old.excludeTelegram, isFalse);
      expect(old.excludeMessenger, isFalse);
    },
  );
  test('unknown duration can be excluded and persists', () {
    final settings = MusicLibrarySettings(includeUnknownDuration: false);
    expect(settings.matches({'path': '/music/a.mp3'}), isFalse);
    expect(
      settings.matches({'path': '/music/b.mp3', 'duration': '0'}),
      isFalse,
    );
    expect(
      settings.matches({'path': '/music/c.mp3', 'duration': '5000'}),
      isTrue,
    );
    expect(
      MusicLibrarySettings.fromJson(settings.toJson()).includeUnknownDuration,
      isFalse,
    );
    expect(MusicLibrarySettings.fromJson({}).includeUnknownDuration, isTrue);
  });
}
