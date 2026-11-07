import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/arc_volume_slider.dart';
import 'package:musicgram/main.dart';
import 'package:musicgram/playback_controller.dart';
import 'package:musicgram/playback_diagnostics.dart';

import 'fake_audio_backend.dart';

class DelayedFilePicker extends FilePickerPlatform {
  final Completer<List<PlatformFile>> result = Completer();

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) => result.future;
}

final class TestLocalFile extends PlatformFile {
  @override
  String get name => 'Local song';
  @override
  Uri get uri => Uri.file('/local');
  @override
  Never get xFile => throw UnimplementedError();
  @override
  int? lengthSync() => 123;
  @override
  Future<int?> length() async => 123;
  @override
  Never readAsBytes() => throw UnimplementedError();
  @override
  Never readAsByteStream() => throw UnimplementedError();
}

void main() {
  testWidgets('Telegram queue shortcuts stay in the same sheet', (
    tester,
  ) async {
    final playback = PlaybackController(backend: FakeAudioBackend());
    addTearDown(playback.dispose);
    await playback.loadQueue(const [
      LocalTrack(name: 'Telegram song', path: '/telegram', telegramFileId: 9),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          leftHanded: false,
          playbackController: playback,
          onHandChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('Next up'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Local'), findsOneWidget);
    final sheet = tester.element(find.byType(BottomSheet));
    await tester.ensureVisible(find.text('Playlists'));
    await tester.tap(find.text('Playlists'));
    await tester.pump();
    expect(tester.element(find.byType(BottomSheet)), same(sheet));
    expect(find.text('Telegram'), findsOneWidget);
    expect(find.text('All songs'), findsOneWidget);
    await tester.tap(find.text('All songs'));
    await tester.pump();
    expect(tester.element(find.byType(BottomSheet)), same(sheet));
    expect(find.text('Local'), findsOneWidget);
  });
  testWidgets('shows Telegram loading intent in the play button', (
    tester,
  ) async {
    final gate = Completer<void>();
    final backend = FakeAudioBackend()..loadGate = gate;
    final player = PlaybackController(backend: backend);
    addTearDown(player.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          leftHanded: false,
          playbackController: player,
          onHandChanged: (_) {},
        ),
      ),
    );
    final loading = player.loadQueue(const [
      LocalTrack(
        name: 'Telegram',
        path: 'http://127.0.0.1/audio',
        telegramFileId: 1,
      ),
    ]);
    await tester.pump();
    expect(find.byTooltip('Pause playback'), findsOneWidget);
    await tester.tap(find.byTooltip('Pause playback'));
    await tester.pump();
    expect(find.byTooltip('Play playback'), findsOneWidget);
    gate.complete();
    await loading;
  });
  testWidgets('playback failure is logged and shown as a toast', (
    tester,
  ) async {
    PlaybackDiagnostics.entries.value = [];
    addTearDown(() => PlaybackDiagnostics.entries.value = []);
    final backend = FakeAudioBackend()..loadError = TimeoutException('slow');
    final player = PlaybackController(backend: backend);
    addTearDown(player.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          leftHanded: false,
          playbackController: player,
          onHandChanged: (_) {},
        ),
      ),
    );
    await player.loadQueue(const [LocalTrack(name: 'Song', path: '/song')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('Could not play Song'), findsOneWidget);
    expect(
      PlaybackDiagnostics.entries.value.join('\n'),
      contains('Could not play selected track'),
    );
  });
  testWidgets('switching between local and Telegram reuses one sheet', (
    tester,
  ) async {
    final playback = PlaybackController(backend: FakeAudioBackend());
    addTearDown(playback.dispose);
    await playback.loadQueue(const [
      LocalTrack(name: 'Local song', path: '/local'),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          leftHanded: false,
          playbackController: playback,
          onHandChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('Next up'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(BottomSheet), findsOneWidget);
    final sheet = tester.element(find.byType(BottomSheet));
    await tester.tap(find.text('Telegram'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.element(find.byType(BottomSheet)), same(sheet));
    expect(
      tester.widget<BottomSheet>(find.byType(BottomSheet)).clipBehavior,
      Clip.antiAlias,
    );
    expect(find.text('Local'), findsOneWidget);
    expect(find.byTooltip('Current queue'), findsNothing);
    expect(
      tester
          .widget<ActionChip>(find.widgetWithText(ActionChip, 'All songs'))
          .side
          ?.width,
      2,
    );
    await tester.tap(find.text('Local'));
    await tester.pump();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.element(find.byType(BottomSheet)), same(sheet));
    expect(find.text('Current queue'), findsOneWidget);
    expect(playback.currentTrack?.name, 'Local song');
  });
  testWidgets('local playlists load and return within the same stable sheet', (
    tester,
  ) async {
    final oldPicker = FilePickerPlatform.instance;
    final picker = DelayedFilePicker();
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = oldPicker);
    final playback = PlaybackController(backend: FakeAudioBackend());
    addTearDown(playback.dispose);
    await playback.loadQueue(const [
      LocalTrack(name: 'Local song', path: '/local'),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          leftHanded: false,
          playbackController: playback,
          onHandChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('Next up'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final sheet = tester.element(find.byType(BottomSheet));
    final originalHeight = tester.getSize(find.byType(BottomSheet)).height;
    await tester.ensureVisible(find.text('Playlists'));
    await tester.tap(find.text('Playlists'));
    await tester.pump();
    expect(tester.element(find.byType(BottomSheet)), same(sheet));
    expect(tester.getSize(find.byType(BottomSheet)).height, originalHeight);
    picker.result.complete([TestLocalFile()]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.element(find.byType(BottomSheet)), same(sheet));
    expect(tester.getSize(find.byType(BottomSheet)).height, originalHeight);
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    expect(tester.element(find.byType(BottomSheet)), same(sheet));
    expect(find.text('Current queue'), findsOneWidget);
  });
  testWidgets('switching to local opens a loading sheet immediately', (
    tester,
  ) async {
    final oldPicker = FilePickerPlatform.instance;
    final picker = DelayedFilePicker();
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = oldPicker);
    final playback = PlaybackController(backend: FakeAudioBackend());
    addTearDown(playback.dispose);
    await playback.loadQueue(const [
      LocalTrack(name: 'Telegram song', path: '/telegram', telegramFileId: 5),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          leftHanded: false,
          playbackController: playback,
          onHandChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('Next up'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Local'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('libraryLoadingSkeleton')), findsOneWidget);
    expect(find.text('Current queue'), findsOneWidget);
    picker.result.complete([TestLocalFile()]);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('libraryLoadingSkeleton')), findsNothing);
    expect(find.text('Local song'), findsOneWidget);
    expect(playback.currentTrack?.name, 'Telegram song');
  });
  for (final left in [false, true]) {
    testWidgets(
      'metadata and playback options fit ${left ? 'left' : 'right'} handed layout',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final playback = PlaybackController(backend: FakeAudioBackend());
        addTearDown(playback.dispose);
        await playback.loadQueue(const [
          LocalTrack(
            name: 'Song',
            path: '/one',
            artist: 'A long artist name',
            album: 'A long album name',
          ),
        ]);
        await tester.pumpWidget(
          MaterialApp(
            home: PlayerScreen(
              leftHanded: left,
              playbackController: playback,
              onHandChanged: (_) {},
            ),
          ),
        );
        final album = tester.getRect(find.byIcon(Icons.album_outlined));
        final repeat = tester.getRect(find.text('Repeat'));
        final shuffle = tester.getRect(find.text('Shuffle'));
        final nextUp = tester.getRect(find.text('Next up'));
        expect(repeat.top, greaterThan(album.bottom));
        expect(shuffle.top, greaterThan(repeat.top));
        expect(shuffle.bottom, lessThan(nextUp.top));
      },
    );
  }
  testWidgets(
    'artist and album open matching songs without changing the queue',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final playback = PlaybackController(backend: FakeAudioBackend());
      addTearDown(playback.dispose);
      await playback.loadQueue(const [
        LocalTrack(
          name: 'First',
          path: '/one',
          artist: 'Artist A',
          album: 'Album A',
        ),
        LocalTrack(
          name: 'Second',
          path: '/two',
          artist: 'Artist A',
          album: 'Album B',
        ),
        LocalTrack(
          name: 'Third',
          path: '/three',
          artist: 'Artist B',
          album: 'Album A',
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            leftHanded: false,
            playbackController: playback,
            onHandChanged: (_) {},
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Second'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Third'),
        ),
        findsNothing,
      );
      expect(playback.queue.length, 3);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byIcon(Icons.album_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Third'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Second'),
        ),
        findsNothing,
      );
      expect(playback.queue.length, 3);
    },
  );
  testWidgets('elapsed and remaining time change on the same second', (
    tester,
  ) async {
    final backend = FakeAudioBackend();
    final playback = PlaybackController(backend: backend);
    addTearDown(playback.dispose);
    await playback.loadQueue(const [LocalTrack(name: 'Song', path: '/song')]);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          leftHanded: false,
          playbackController: playback,
          onHandChanged: (_) {},
        ),
      ),
    );
    backend.durations.add(const Duration(milliseconds: 10600));
    backend.positions.add(const Duration(milliseconds: 700));
    await tester.pump();
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('-00:10'), findsOneWidget);
    backend.positions.add(const Duration(milliseconds: 1100));
    await tester.pump();
    expect(find.text('00:01'), findsOneWidget);
    expect(find.text('-00:09'), findsOneWidget);
  });
  testWidgets('current track menu offers playlist and info actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final playback = PlaybackController(backend: FakeAudioBackend());
    addTearDown(playback.dispose);
    await playback.loadQueue(const [LocalTrack(name: 'Song', path: '/song')]);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          leftHanded: false,
          playbackController: playback,
          onHandChanged: (_) {},
        ),
      ),
    );
    final menu = tester.widget<PopupMenuButton<String>>(
      find.byType(PopupMenuButton<String>),
    );
    expect((menu.icon as Icon).icon, Icons.menu);
    expect(menu.style?.backgroundColor?.resolve({}), isNotNull);
    expect(
      menu.style?.foregroundColor?.resolve({}),
      tester
          .widget<IconButton>(find.byKey(const Key('settingsButton')))
          .style
          ?.foregroundColor
          ?.resolve({}),
    );
    final positioned = tester.widget<Positioned>(
      find
          .ancestor(
            of: find.byTooltip('Current track actions'),
            matching: find.byType(Positioned),
          )
          .first,
    );
    expect(positioned.bottom, 8);
    expect(
      find.descendant(
        of: find.byKey(const Key('artworkHeader')),
        matching: find.byTooltip('Current track actions'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Current track actions'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Add to playlist'), findsOneWidget);
    expect(find.text('Download track'), findsNothing);
    await tester.tap(find.text('Music info'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Song'),
      ),
      findsOneWidget,
    );
    expect(find.text('Source'), findsOneWidget);
  });
  testWidgets('record rotates while playing and pauses in place', (
    tester,
  ) async {
    final playback = PlaybackController(backend: FakeAudioBackend());
    addTearDown(playback.dispose);
    await playback.loadQueue(const [LocalTrack(name: 'First', path: '/one')]);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          leftHanded: false,
          playbackController: playback,
          onHandChanged: (_) {},
        ),
      ),
    );
    final record = find.descendant(
      of: find.byKey(const Key('circularSeek')),
      matching: find.byType(RotationTransition),
    );
    await tester.pump(const Duration(seconds: 1));
    final first = tester.widget<RotationTransition>(record).turns.value;
    await tester.pump(const Duration(seconds: 1));
    expect(
      tester.widget<RotationTransition>(record).turns.value,
      greaterThan(first),
    );
    await playback.pause();
    await tester.pump();
    final paused = tester.widget<RotationTransition>(record).turns.value;
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<RotationTransition>(record).turns.value, paused);
  });

  testWidgets('disabling artwork swipes prevents changing tracks', (
    tester,
  ) async {
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final playback = PlaybackController(backend: FakeAudioBackend());
    addTearDown(playback.dispose);
    await playback.loadQueue(const [
      LocalTrack(name: 'First', path: '/one'),
      LocalTrack(name: 'Second', path: '/two'),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          leftHanded: false,
          playbackController: playback,
          onHandChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('settingsButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Playback'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Swipe artwork to change tracks'),
      200,
    );
    await tester.tap(find.text('Swipe artwork to change tracks'));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Save changes'), 200);
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.fling(
      find.byKey(const Key('swipeableArtwork')),
      const Offset(-200, 0),
      800,
    );
    await tester.pump(const Duration(milliseconds: 800));
    expect(playback.currentIndex, 0);
  });
  testWidgets('swiping artwork changes tracks in both directions', (
    tester,
  ) async {
    final backend = FakeAudioBackend();
    final playback = PlaybackController(backend: backend);
    addTearDown(playback.dispose);
    await playback.loadQueue(const [
      LocalTrack(name: 'First', path: '/one'),
      LocalTrack(name: 'Second', path: '/two'),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          leftHanded: false,
          playbackController: playback,
          onHandChanged: (_) {},
        ),
      ),
    );
    final artwork = find.byKey(const Key('swipeableArtwork'));
    final gesture = await tester.startGesture(tester.getCenter(artwork));
    await gesture.moveBy(const Offset(-100, 0));
    await tester.pump();
    final pageView = tester.widget<PageView>(artwork);
    expect(pageView.controller!.page!, greaterThan(10000));
    await gesture.moveBy(const Offset(100, 0));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.fling(
      find.byKey(const Key('swipeableArtwork')),
      const Offset(-200, 0),
      800,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(playback.currentIndex, 1);
    expect(pageView.controller!.page, 10001);
    expect(find.byKey(const Key('swipeableArtwork')), findsOneWidget);
    backend.positions.add(const Duration(seconds: 15));
    await tester.pump();
    await tester.fling(
      find.byKey(const Key('swipeableArtwork')),
      const Offset(200, 0),
      800,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(playback.currentIndex, 0);
  });
  testWidgets('active All songs shortcut keeps the queue sheet open', (
    tester,
  ) async {
    final playback = PlaybackController(backend: FakeAudioBackend());
    addTearDown(playback.dispose);
    await playback.loadQueue(const [
      LocalTrack(name: 'First', path: '/one'),
    ], allSongs: true);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          leftHanded: false,
          playbackController: playback,
          onHandChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('Next up'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final shortcut = tester.widget<ActionChip>(
      find.widgetWithText(ActionChip, 'All songs'),
    );
    expect(shortcut.side?.width, 2);
    await tester.tap(find.text('All songs'));
    await tester.pump();
    expect(find.text('Current queue'), findsOneWidget);
    expect(playback.isAllSongsQueue, isTrue);
  });
  testWidgets('open queue updates highlight as playback advances', (
    tester,
  ) async {
    final playback = PlaybackController(backend: FakeAudioBackend());
    addTearDown(playback.dispose);
    await playback.loadQueue(const [
      LocalTrack(name: 'First', path: '/one'),
      LocalTrack(name: 'Second', path: '/two'),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          leftHanded: false,
          playbackController: playback,
          onHandChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('Next up'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final firstBefore = tester
        .widget<Text>(find.text('First').last)
        .style!
        .color;
    final secondBefore = tester
        .widget<Text>(find.text('Second').last)
        .style!
        .color;
    expect(firstBefore, isNotNull);
    expect(secondBefore, isNull);
    await playback.next();
    await tester.pump();
    expect(tester.widget<Text>(find.text('First').last).style!.color, isNull);
    expect(
      tester.widget<Text>(find.text('Second').last).style!.color,
      firstBefore,
    );
  });

  testWidgets('cast is available from track menu instead of settings', (
    tester,
  ) async {
    final player = PlaybackController(backend: FakeAudioBackend());
    addTearDown(player.dispose);
    await player.loadQueue(const [
      LocalTrack(name: 'Song', path: '/song'),
    ], autoplay: false);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          leftHanded: false,
          playbackController: player,
          onHandChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('settingsButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Cast to device'), findsNothing);
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('Current track actions'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Cast to device'), findsOneWidget);
  });

  testWidgets('hand preference changes the player layout', (tester) async {
    var leftHanded = false;
    final playback = PlaybackController(backend: FakeAudioBackend());
    addTearDown(playback.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => PlayerScreen(
            leftHanded: leftHanded,
            playbackController: playback,
            onHandChanged: (value) => setState(() => leftHanded = value),
          ),
        ),
      ),
    );
    expect(find.text('Choose a song'), findsWidgets);
    await tester.tap(find.byKey(const Key('settingsButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Appearance'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.text('Left-handed'));
    await tester.pump();
    await tester.tap(find.text('Left-handed'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(leftHanded, isTrue);
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      tester.widget<ArcVolumeSlider>(find.byType(ArcVolumeSlider)).leftHanded,
      isTrue,
    );
  });

  for (final leftHanded in [false, true]) {
    testWidgets(
      'volume arc reaches both ends in ${leftHanded ? 'left' : 'right'} mode',
      (tester) async {
        double value = .5;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => ArcVolumeSlider(
                  value: value,
                  leftHanded: leftHanded,
                  onChanged: (next) => setState(() => value = next),
                ),
              ),
            ),
          ),
        );
        final origin = tester.getTopLeft(find.byType(ArcVolumeSlider));
        final minPoint = origin + Offset(leftHanded ? 249 : 51, 258);
        final maxPoint = origin + Offset(leftHanded ? 42 : 258, 51);
        await tester.tapAt(minPoint);
        await tester.pump();
        expect(value, closeTo(0, .04));
        await tester.tapAt(maxPoint);
        await tester.pump();
        expect(value, closeTo(1, .04));
      },
    );
  }
}
