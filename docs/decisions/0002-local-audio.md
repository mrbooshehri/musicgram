# Local audio playback

Use `file_picker` to let users choose one or more audio files and `audioplayers` to play them on Android, Linux, and Windows. Keep playback state and queue navigation in a small `PlaybackController`; the `AudioBackend` interface exists at this plugin boundary so controller behavior can be tested without native audio. The curved volume control adjusts app playback volume. File selection and playback are foreground only; the queue lasts for the current app session.

Package resolution succeeded in the developer environment. This workspace cannot run the Flutter test runner because local loopback sockets are denied, and it lacks Android SDK and Linux CMake, so native playback has not been smoke-tested here.
