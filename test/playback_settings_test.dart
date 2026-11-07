import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/playback_settings.dart';

void main() {
  test('playback settings preserve choices and fall back safely', () {
    final settings = PlaybackSettings(
      resumeOnLaunch: true,
      repeat: PlaybackDefault.on,
      shuffle: PlaybackDefault.off,
    );
    final restored = PlaybackSettings.fromJson(settings.toJson());
    expect(restored.resumeOnLaunch, isTrue);
    expect(PlaybackSettings.resolve(restored.repeat, false), isTrue);
    expect(PlaybackSettings.resolve(restored.shuffle, true), isFalse);
    expect(PlaybackSettings.resolve(PlaybackDefault.remember, true), isTrue);
    expect(PlaybackSettings.resolve(PlaybackDefault.remember, false), isFalse);
    expect(
      PlaybackSettings.fromJson({'repeat': 'invalid'}).repeat,
      PlaybackDefault.remember,
    );
    expect(PlaybackSettings().resumeOnLaunch, isFalse);
  });
  test('playback behavior options persist and validate input', () {
    final settings = PlaybackSettings(
      artworkSwipe: false,
      previousRestartSeconds: 5,
    );
    final restored = PlaybackSettings.fromJson(settings.toJson());
    expect(restored.artworkSwipe, isFalse);
    expect(restored.previousRestartSeconds, 5);
    expect(
      PlaybackSettings.fromJson({'previousRestartSeconds': -1})
          .previousRestartSeconds,
      3,
    );
    expect(PlaybackSettings().artworkSwipe, isTrue);
  });
}
