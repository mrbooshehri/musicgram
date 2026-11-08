import 'dart:io';
import 'dart:async';

import 'embedded_artwork.dart';
import 'generated_artwork.dart';

import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import 'app_snack_bar.dart';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'arc_volume_slider.dart';
import 'appearance_settings.dart';
import 'about_diagnostics_screen.dart';
import 'diagnostics_logs_screen.dart';
import 'notification_settings.dart';
import 'notification_settings_screen.dart';
import 'playback_controller.dart';
import 'playback_settings.dart';
import 'playback_settings_screen.dart';
import 'telegram_screen.dart';
import 'telegram_library_sheet.dart';
import 'loading_skeleton.dart';
import 'lyrics_sheet.dart';
import 'library_search.dart';
import 'mini_player.dart';
import 'upnp_discovery_screen.dart';
import 'telegram_client.dart';
import 'telegram_stream_server.dart';
import 'telegram_playback_log.dart';
import 'telegram_artwork.dart';
import 'telegram_music_library.dart';
import 'telegram_library_cache.dart';
import 'telegram_sync_job.dart';
import 'telegram_background_recovery.dart';
import 'download_settings.dart';
import 'download_settings_screen.dart';
import 'downloaded_tracks.dart';
import 'playlist_settings_screen.dart';
import 'playlist_store.dart';
import 'local_library_screen.dart';
import 'local_category_sheet.dart';
import 'music_library_settings.dart';
import 'music_library_settings_screen.dart';
import 'queue_shortcut_settings.dart';
import 'playlist_queue_settings_screen.dart';

const _background = Color(0xFF101B27);
const _surface = Color(0xFF202B39);
const _accent = Color(0xFFF5295C);

enum AppPalette {
  gram,
  dracula,
  gruvbox,
  nord,
  catppuccin,
  tokyo,
  solarized,
  oneDark,
}

final ValueNotifier<AppPalette> appPalette = ValueNotifier(AppPalette.gram);

final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier(ThemeMode.dark);
final ValueNotifier<Color?> customAccent = ValueNotifier(null);
final ValueNotifier<Map<String, int>> customThemeColors = ValueNotifier({});
final appearanceStore = AppearanceSettingsStore();

void saveAppearance() {
  unawaited(
    appearanceStore
        .save(
          AppearanceSettings(
            mode: appThemeMode.value.name,
            palette: appPalette.value.name,
            accent: customAccent.value?.toARGB32(),
            colors: customThemeColors.value,
          ),
        )
        .catchError((_) {}),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const MethodChannel('musicgram/telegram_sync_recovery')
      .setMethodCallHandler((call) async {
        if (call.method == 'resume') TelegramBackgroundRecovery.start();
      });
  if (WidgetsBinding.instance.platformDispatcher.defaultRouteName ==
      '/telegram-sync-recovery') {
    TelegramBackgroundRecovery.start();
  }
  await QueueShortcutSettings.load();
  try {
    await NotificationSettings.load();
  } catch (_) {
    // Use the default if notification preferences cannot be loaded.
  }
  try {
    final appearance = await appearanceStore.load();
    appThemeMode.value = ThemeMode.values.firstWhere(
      (v) => v.name == appearance.mode,
    );
    appPalette.value = AppPalette.values.firstWhere(
      (v) => v.name == appearance.palette,
    );
    customThemeColors.value = appearance.colors;
    customAccent.value = appearance.accent == null
        ? null
        : Color(appearance.accent!);
  } catch (_) {
    // Keep the default appearance if storage is unavailable.
  }
  try {
    await DownloadSettings.shared.load();
  } catch (_) {
    /* Use defaults if settings are unavailable. */
  }
  try {
    await DownloadedTracks.shared.load();
  } catch (_) {
    /* Download status is unavailable. */
  }
  final settings = HandPreferenceStore();
  final leftHanded = await settings.load();
  runApp(MusicGramApp(settings: settings, initialLeftHanded: leftHanded));
}

class HandPreferenceStore {
  Future<File> _file() async => File(
    '${(await getApplicationSupportDirectory()).path}/hand_preference.txt',
  );

  Future<bool> load() async {
    try {
      return (await (await _file()).readAsString()).trim() == 'left';
    } on FileSystemException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> save(bool leftHanded) async {
    final file = await _file();
    await file.create(recursive: true);
    await file.writeAsString(leftHanded ? 'left' : 'right');
  }
}

class MusicGramApp extends StatefulWidget {
  const MusicGramApp({
    super.key,
    required this.settings,
    required this.initialLeftHanded,
  });

  final HandPreferenceStore settings;
  final bool initialLeftHanded;

  @override
  State<MusicGramApp> createState() => _MusicGramAppState();
}

class _MusicGramAppState extends State<MusicGramApp> {
  late bool leftHanded = widget.initialLeftHanded;
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _miniPlayerObserver = MiniPlayerNavigatorObserver();
  final _miniPlayerController = ValueNotifier<PlaybackController?>(null);

  @override
  void dispose() {
    _miniPlayerObserver.dispose();
    _miniPlayerController.dispose();
    super.dispose();
  }

  void changeHand(bool value) {
    setState(() => leftHanded = value);
    widget.settings.save(value);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppPalette>(
    valueListenable: appPalette,
    builder: (context, palette, _) => ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (context, mode, _) => ValueListenableBuilder<Color?>(
        valueListenable: customAccent,
        builder: (context, selectedAccent, _) =>
            ValueListenableBuilder<Map<String, int>>(
              valueListenable: customThemeColors,
              builder: (context, colors, _) {
                final (
                  darkBg,
                  darkSurface,
                  darkText,
                  accent,
                  lightBg,
                  lightSurface,
                  lightText,
                ) = switch (palette) {
                  AppPalette.gram => (
                    _background,
                    _surface,
                    const Color(0xFFF4F4F6),
                    _accent,
                    Colors.white,
                    const Color(0xFFF0F3F6),
                    _background,
                  ),
                  AppPalette.dracula => (
                    const Color(0xFF282A36),
                    const Color(0xFF44475A),
                    const Color(0xFFF8F8F2),
                    const Color(0xFFFF79C6),
                    const Color(0xFFF8F8F2),
                    const Color(0xFFE8E8E3),
                    const Color(0xFF282A36),
                  ),
                  AppPalette.gruvbox => (
                    const Color(0xFF282828),
                    const Color(0xFF3C3836),
                    const Color(0xFFEBDBB2),
                    const Color(0xFFFB4934),
                    const Color(0xFFFBF1C7),
                    const Color(0xFFEBDBB2),
                    const Color(0xFF3C3836),
                  ),
                  AppPalette.nord => (
                    const Color(0xFF2E3440),
                    const Color(0xFF3B4252),
                    const Color(0xFFECEFF4),
                    const Color(0xFF88C0D0),
                    const Color(0xFFECEFF4),
                    const Color(0xFFE5E9F0),
                    const Color(0xFF2E3440),
                  ),
                  AppPalette.catppuccin => (
                    const Color(0xFF1E1E2E),
                    const Color(0xFF313244),
                    const Color(0xFFCDD6F4),
                    const Color(0xFFCBA6F7),
                    const Color(0xFFEFF1F5),
                    const Color(0xFFE6E9EF),
                    const Color(0xFF4C4F69),
                  ),
                  AppPalette.tokyo => (
                    const Color(0xFF1A1B26),
                    const Color(0xFF24283B),
                    const Color(0xFFC0CAF5),
                    const Color(0xFF7AA2F7),
                    const Color(0xFFD5D6DB),
                    const Color(0xFFE6E7ED),
                    const Color(0xFF343B58),
                  ),
                  AppPalette.solarized => (
                    const Color(0xFF002B36),
                    const Color(0xFF073642),
                    const Color(0xFFEEE8D5),
                    const Color(0xFF2AA198),
                    const Color(0xFFFDF6E3),
                    const Color(0xFFEEE8D5),
                    const Color(0xFF073642),
                  ),
                  AppPalette.oneDark => (
                    const Color(0xFF282C34),
                    const Color(0xFF3E4451),
                    const Color(0xFFABB2BF),
                    const Color(0xFF61AFEF),
                    const Color(0xFFFAFAFA),
                    const Color(0xFFEAEAEB),
                    const Color(0xFF383A42),
                  ),
                };
                Color role(String key, Color fallback) =>
                    colors[key] == null ? fallback : Color(colors[key]!);
                final darkBackground = role('dark.background', darkBg);
                final darkCard = role('dark.surface', darkSurface);
                final darkForeground = role('dark.text', darkText);
                final darkPrimary = role(
                  'dark.accent',
                  selectedAccent ?? accent,
                );
                final lightBackground = role('light.background', lightBg);
                final lightCard = role('light.surface', lightSurface);
                final lightForeground = role('light.text', lightText);
                final lightPrimary = role(
                  'light.accent',
                  selectedAccent ?? accent,
                );
                Color onPrimary(Color color) =>
                    ThemeData.estimateBrightnessForColor(color) ==
                        Brightness.dark
                    ? Colors.white
                    : Colors.black;
                return MaterialApp(
                  title: 'MusicGram',
                  navigatorKey: _navigatorKey,
                  navigatorObservers: [_miniPlayerObserver],
                  builder: (context, child) => MiniPlayerShell(
                    player: _miniPlayerController,
                    secondaryPage: _miniPlayerObserver.secondaryPage,
                    onOpenPlayer: () => _navigatorKey.currentState?.popUntil(
                      (route) => route.isFirst,
                    ),
                    child: child!,
                  ),
                  debugShowCheckedModeBanner: false,
                  themeMode: mode,
                  darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
                    scaffoldBackgroundColor: darkBackground,
                    textTheme: ThemeData.dark().textTheme.apply(
                      bodyColor: darkForeground,
                      displayColor: darkForeground,
                    ),
                    iconTheme: IconThemeData(color: darkForeground),
                    appBarTheme: AppBarTheme(
                      backgroundColor: darkCard,
                      foregroundColor: darkForeground,
                    ),
                    colorScheme: ColorScheme.dark(
                      primary: darkPrimary,
                      onPrimary: onPrimary(darkPrimary),
                      surface: darkCard,
                      onSurface: darkForeground,
                      onSurfaceVariant: darkForeground.withValues(alpha: .8),
                    ),
                  ),
                  theme: ThemeData.light(useMaterial3: true).copyWith(
                    scaffoldBackgroundColor: lightBackground,
                    textTheme: ThemeData.light().textTheme.apply(
                      bodyColor: lightForeground,
                      displayColor: lightForeground,
                    ),
                    iconTheme: IconThemeData(color: lightForeground),
                    appBarTheme: AppBarTheme(
                      backgroundColor: lightCard,
                      foregroundColor: lightForeground,
                    ),
                    colorScheme: ColorScheme.light(
                      primary: lightPrimary,
                      onPrimary: onPrimary(lightPrimary),
                      surface: lightCard,
                      onSurface: lightForeground,
                      onSurfaceVariant: lightForeground.withValues(alpha: .8),
                    ),
                  ),
                  home: PlayerScreen(
                    leftHanded: leftHanded,
                    onHandChanged: changeHand,
                    onPlaybackReady: (player) {
                      if (mounted) _miniPlayerController.value = player;
                    },
                  ),
                );
              },
            ),
      ),
    ),
  );
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.leftHanded,
    required this.onHandChanged,
    this.playbackController,
    this.onPlaybackReady,
  });
  final bool leftHanded;
  final ValueChanged<bool> onHandChanged;
  final PlaybackController? playbackController;
  final ValueChanged<PlaybackController>? onPlaybackReady;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  String? _lastPlaybackError;
  late final PlaybackController _playback;
  late final bool _ownsPlayback;
  int _playbackOptionsRevision = 0;
  bool _artworkSwipeEnabled = true;
  PlayerAudioHandler? _audioHandler;
  bool _telegramBootstrapActive = false;
  final ValueNotifier<TelegramSheetStatus> _telegramSheetStatus = ValueNotifier(
    (state: 'initializing', error: null),
  );
  TelegramStreamServer _telegramStream = TelegramStreamServer(
    TelegramClient.shared.request,
  );
  final Set<String> _downloading = {};
  void _onDownloadStatusChanged() {
    if (mounted) setState(() {});
  }

  void _onProxyConnectionChanged() {
    if (mounted) setState(() {});
  }

  Widget _proxyIcon() => Builder(
    builder: (context) => TelegramClient.shared.proxyConnected
        ? const Icon(Icons.verified_user_outlined, size: 20)
        : SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: IconTheme.of(context).color,
              semanticsLabel: 'Connecting to proxy',
            ),
          ),
  );

  Future<void> _addCurrentToPlaylist(LocalTrack song) async {
    try {
      final store = PlaylistStore();
      final playlists = await store.load();
      if (!mounted) return;
      final telegram = song.telegramFileId != null;
      final indices = [
        for (var i = 0; i < playlists.length; i++)
          if (playlists[i]['type'] == (telegram ? 'telegram' : 'local')) i,
      ];
      if (indices.isEmpty) {
        _showMessage(
          'Create a ${telegram ? 'Telegram' : 'local'} playlist in Settings first.',
        );
        return;
      }
      var playlistSearch = '';
      final selected = await showModalBottomSheet<int>(
        context: context,
        isScrollControlled: true,
        builder: (context) => StatefulBuilder(
          builder: (context, update) {
            final visible = indices
                .where(
                  (index) => librarySearchMatches(
                    playlists[index]['name']?.toString() ?? 'Playlist',
                    playlistSearch,
                  ),
                )
                .toList();
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SafeArea(
                child: SizedBox(
                  height:
                      (MediaQuery.sizeOf(context).height * .65 -
                              MediaQuery.viewInsetsOf(context).bottom)
                          .clamp(200.0, double.infinity),
                  child: Column(
                    children: [
                      const ListTile(title: Text('Add to playlist')),
                      Expanded(
                        child: ListView.builder(
                          itemCount: visible.length,
                          itemBuilder: (context, position) {
                            final index = visible[position];
                            return ListTile(
                              leading: const Icon(Icons.queue_music),
                              title: Text(
                                playlists[index]['name']?.toString() ??
                                    'Playlist',
                              ),
                              onTap: () => Navigator.pop(context, index),
                            );
                          },
                        ),
                      ),
                      LibrarySearch(
                        hint: 'Search playlists',
                        onChanged: (value) =>
                            update(() => playlistSearch = value),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
      if (selected == null) return;
      final item = playlists[selected];
      final entries = ((item['tracks'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final message = song.telegramMessage;
      if (telegram && message == null) {
        if (mounted) {
          _showMessage(
            'Telegram track details are unavailable.',
            kind: AppNoticeKind.error,
          );
        }
        return;
      }
      final entry = telegram
          ? message!
          : <String, dynamic>{
              'path': song.path,
              'name': song.name,
              'title': song.title,
              'artist': song.artist,
              'album': song.album,
              'genre': song.genre,
            };
      final alreadyAdded = entries.any(
        (existing) => telegram
            ? existing['chat_id'] == entry['chat_id'] &&
                  existing['id'] == entry['id']
            : existing['path'] == entry['path'],
      );
      if (alreadyAdded) {
        if (mounted) {
          _showMessage(
            'Track is already in this playlist.',
            kind: AppNoticeKind.warning,
          );
        }
        return;
      }
      playlists[selected] = {
        ...item,
        'tracks': [...entries, entry],
      };
      await store.save(playlists);
      if (mounted) {
        _showMessage('Added to ${item['name']}', kind: AppNoticeKind.success);
      }
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Could not add track to playlist.',
          kind: AppNoticeKind.error,
        );
      }
    }
  }

  void _showTrackInfo(LocalTrack song) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Music info'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _cover(song, size: 64),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.displayTitle,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          song.displayArtist,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: _mutedColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ...[
                if (song.album?.isNotEmpty == true) ('Album', song.album!),
                if (song.genre?.isNotEmpty == true) ('Genre', song.genre!),
                ('Source', song.telegramFileId != null ? 'Telegram' : 'Local'),
                ('Duration', _formatTime(_playback.duration)),
              ].map(
                (detail) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        detail.$1,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: _mutedColor),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail.$2,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _playlistDownloads = Future.value();
  int _pendingDownloadBatches = 0;
  int _pendingTelegramDownloads = 0;
  int _activeDownloads = 0;
  final List<Completer<void>> _downloadWaiters = [];

  Future<void> _acquireDownload() async {
    if (_activeDownloads < DownloadSettings.shared.concurrency) {
      _activeDownloads++;
      return;
    }
    final waiter = Completer<void>();
    _downloadWaiters.add(waiter);
    await waiter.future;
  }

  void _releaseDownload() {
    _activeDownloads--;
    while (_downloadWaiters.isNotEmpty &&
        _activeDownloads < DownloadSettings.shared.concurrency) {
      _activeDownloads++;
      _downloadWaiters.removeAt(0).complete();
    }
  }

  void _queuePlaylistDownload(List<Map<String, dynamic>> tracks, String name) {
    final items = List<Map<String, dynamic>>.of(tracks);
    _pendingDownloadBatches++;
    _playlistDownloads = _playlistDownloads.then((_) async {
      try {
        await Future.wait(
          items.map((message) async {
            try {
              await _downloadTelegramMessage(message, name);
            } catch (error) {
              if (mounted) {
                _showMessage(
                  'Download failed: $error',
                  kind: AppNoticeKind.error,
                );
              }
            }
          }),
        );
      } finally {
        _pendingDownloadBatches--;
      }
    });
  }

  Future<void> _prepareTelegramSignOut() async {
    if (_pendingDownloadBatches > 0 ||
        _pendingTelegramDownloads > 0 ||
        _downloading.isNotEmpty ||
        _activeDownloads > 0) {
      throw StateError(
        'Wait for Telegram downloads to finish before signing out.',
      );
    }
    _stopTelegramBootstrap();
    await _playback.clearTelegramQueue();
    final previous = _telegramStream;
    await previous.close();
    _telegramStream = TelegramStreamServer(TelegramClient.shared.request);
  }

  Future<void> _downloadTelegramMessage(
    Map<String, dynamic> message,
    String playlist,
  ) async {
    _pendingTelegramDownloads++;
    try {
      final content = message['content'];
      final media = content is Map
          ? content['audio'] ?? content['document']
          : null;
      final file = media is Map ? media['audio'] ?? media['document'] : null;
      if (file is! Map ||
          file['id'] is! int ||
          file['size'] is! int ||
          (file['size'] as int) <= 0) {
        throw StateError('Telegram has not provided the audio file size.');
      }
      final name = media is Map && media['file_name'] is String
          ? media['file_name'] as String
          : 'Telegram track';
      final path = await _telegramStream.register(
        file['id'] as int,
        file['size'] as int,
        remoteId: _telegramRemoteId(file),
        chatId: message['chat_id'] is int ? message['chat_id'] as int : null,
        messageId: message['id'] is int ? message['id'] as int : null,
      );
      await _downloadTelegram(
        LocalTrack(
          name: name,
          path: path,
          telegramFileId: file['id'] as int,
          playlistName: playlist,
          downloadKey: DownloadedTracks.keyFor(message),
        ),
      );
    } finally {
      _pendingTelegramDownloads--;
    }
  }

  String? _telegramRemoteId(Map file) {
    final remote = file['remote'];
    return remote is Map && remote['id'] is String
        ? remote['id'] as String
        : null;
  }

  Future<void> _downloadTelegram(LocalTrack song) async {
    if (song.telegramFileId == null ||
        DownloadedTracks.shared.contains(song.downloadKey) ||
        !_downloading.add(song.path)) {
      return;
    }
    await _acquireDownload();
    if (mounted) _showMessage('Downloading ${song.displayTitle}…');
    try {
      final safeFolder = (song.playlistName ?? 'Telegram')
          .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
          .trim();
      final safeName = song.name
          .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
          .trim();
      final tempDir = await Directory.systemTemp.createTemp(
        'musicgram_download_',
      );
      final temp = File('${tempDir.path}/audio');
      final client = HttpClient();
      try {
        final response = await (await client.getUrl(Uri.parse(song.path)))
            .close();
        if (response.statusCode != 200) throw StateError('Download failed');
        final sink = temp.openWrite();
        try {
          await response.pipe(sink);
        } finally {
          await sink.close();
        }
        if (await temp.length() != response.contentLength) {
          throw StateError('Download was incomplete');
        }
        final uri = await const MethodChannel('musicgram/library')
            .invokeMethod<String>('saveTelegramDownload', {
              'path': temp.path,
              'name': safeName.isEmpty || safeName == '.' || safeName == '..'
                  ? '${song.telegramFileId}.audio'
                  : safeName,
              'folder':
                  safeFolder.isEmpty || safeFolder == '.' || safeFolder == '..'
                  ? 'Telegram'
                  : safeFolder,
              'rootFolder': DownloadSettings.shared.folder,
            });
        if (uri != null) {
          await DownloadedTracks.shared.mark(song.downloadKey, uri);
        }
      } finally {
        client.close(force: true);
        await tempDir.delete(recursive: true);
      }
      if (mounted) {
        _showMessage(
          'Downloaded ${song.displayTitle}',
          kind: AppNoticeKind.success,
        );
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Download failed: $e', kind: AppNoticeKind.error);
      }
    } finally {
      _downloading.remove(song.path);
      _releaseDownload();
    }
  }

  Future<void> _playTelegram(
    List<Map<String, dynamic>> messages,
    int selected,
    String playlistName,
  ) async {
    TelegramPlaybackLog.record(
      'Track selected: playlist items=${messages.length}, index=$selected, TDLib running=${TelegramClient.shared.isRunning}, authorized=${TelegramClient.shared.authorizationState == 'authorizationStateReady'}, connected=${TelegramClient.shared.connected}',
    );
    final tracks = <LocalTrack>[];
    var initial = 0;
    for (var i = 0; i < messages.length; i++) {
      final content = messages[i]['content'];
      if (content is! Map) continue;
      final media = content['audio'] ?? content['document'];
      if (media is! Map) continue;
      final file = media['audio'] ?? media['document'];
      final key = DownloadedTracks.keyFor(messages[i]);
      final savedUri = DownloadedTracks.shared.uriFor(key);
      if (file is! Map ||
          file['id'] is! int ||
          (savedUri == null &&
              (file['size'] is! int || (file['size'] as int) <= 0))) {
        continue;
      }
      if (i == selected) initial = tracks.length;
      final name = (media['title'] as String?)?.trim();
      final filename = (media['file_name'] as String?)?.trim();
      tracks.add(
        LocalTrack(
          name: (filename?.isNotEmpty ?? false) ? filename! : 'Telegram track',
          title: name,
          artist: media['performer'] as String?,
          telegramFileId: file['id'] as int,
          downloadKey: key,
          telegramMessage: messages[i],
          playlistName: playlistName,
          path: savedUri != null
              ? (await const MethodChannel('musicgram/library')
                        .invokeMethod<String>('localAudioPath', {
                          'uri': savedUri,
                        }) ??
                    (throw StateError('Local audio unavailable')))
              : await _telegramStream.register(
                  file['id'] as int,
                  file['size'] as int,
                  remoteId: _telegramRemoteId(file),
                  chatId: messages[i]['chat_id'] is int
                      ? messages[i]['chat_id'] as int
                      : null,
                  messageId: messages[i]['id'] is int
                      ? messages[i]['id'] as int
                      : null,
                ),
        ),
      );
    }
    final selectedContent = messages[selected]['content'];
    final selectedMedia = selectedContent is Map
        ? selectedContent['audio'] ?? selectedContent['document']
        : null;
    final selectedFile = selectedMedia is Map
        ? selectedMedia['audio'] ?? selectedMedia['document']
        : null;
    if (selectedFile is! Map ||
        (DownloadedTracks.shared.uriFor(
                  DownloadedTracks.keyFor(messages[selected]),
                ) ==
                null &&
            (selectedFile['size'] is! int ||
                (selectedFile['size'] as int) <= 0))) {
      TelegramPlaybackLog.record('Selected audio has no usable file size');
      throw StateError('Telegram has not provided the audio size.');
    }
    TelegramPlaybackLog.record(
      'Player queue prepared: ${tracks.length} playable items',
    );
    await _playback.loadQueue(tracks, initialIndex: initial);
  }

  Future<void> _playSavedPlaylist(
    Map<String, dynamic> playlist,
    int index,
  ) async {
    final tracks = ((playlist['tracks'] as List?) ?? [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    if (index < 0 || index >= tracks.length) {
      throw StateError('Track is unavailable');
    }
    if (playlist['type'] == 'telegram') {
      await _playTelegram(
        tracks,
        index,
        playlist['name']?.toString() ?? 'Telegram',
      );
      return;
    }
    final queue = <LocalTrack>[];
    var selected = -1;
    for (var i = 0; i < tracks.length; i++) {
      final row = tracks[i];
      final path = row['path'];
      if (path is! String || path.isEmpty) continue;
      if (i == index) selected = queue.length;
      queue.add(
        LocalTrack(
          path: path,
          name: row['name']?.toString() ?? 'Local track',
          title: row['title'] as String?,
          artist: row['artist'] as String?,
          album: row['album'] as String?,
        ),
      );
    }
    if (selected < 0) throw StateError('Local file is unavailable');
    await _playback.loadQueue(queue, initialIndex: selected);
  }

  Timer? _saveTimer;
  bool _restoring = true;
  bool _proxyEnabled = false;

  Future<void> _refreshProxyState() async {
    try {
      final raw = await const FlutterSecureStorage().read(
        key: 'telegram_proxies',
      );
      final enabled =
          raw != null &&
          (jsonDecode(raw) as Map<String, dynamic>)['enabled'] == true;
      if (mounted) setState(() => _proxyEnabled = enabled);
    } catch (_) {
      if (mounted) setState(() => _proxyEnabled = false);
    }
  }

  Future<void> _openProxyList() async {
    _stopTelegramBootstrap();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TelegramScreen(
          onBeforeSignOut: _prepareTelegramSignOut,
          openProxyList: true,
          onPlay: _playTelegram,
          onDownload: _downloadTelegramMessage,
          onDownloadPlaylist: _queuePlaylistDownload,
          onOpenLocal: _switchToLocal,
        ),
      ),
    );
    await _refreshProxyState();
  }

  Color get _surfaceColor => Theme.of(context).colorScheme.surface;
  Color get _mutedColor =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: .7);
  Color get _accentColor => Theme.of(context).colorScheme.primary;
  LocalTrack? get track => _playback.currentTrack;

  @override
  void initState() {
    super.initState();
    TelegramClient.shared.addListener(_onProxyConnectionChanged);
    DownloadedTracks.shared.addListener(_onDownloadStatusChanged);
    _ownsPlayback = widget.playbackController == null;
    _playback = widget.playbackController ?? PlaybackController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onPlaybackReady?.call(_playback);
    });
    _playback.addListener(_onPlaybackChanged);
    if (_ownsPlayback) unawaited(_loadPlaybackOptions());
    if (_ownsPlayback) unawaited(_refreshProxyState());
    if (_ownsPlayback && Platform.isAndroid) {
      _startAudioService();
      unawaited(_recoverTelegramSync());
    } else {
      _restoring = false;
    }
  }

  Future<void> _recoverTelegramSync() async {
    try {
      final recovering = TelegramBackgroundRecovery.running;
      if (recovering != null) {
        await recovering;
        return;
      }
      if (!await TelegramSyncJob.shared.hasPendingActiveSession() || !mounted) {
        return;
      }
      if (TelegramClient.shared.isAccountVerified) {
        await TelegramSyncJob.shared.resumeInterrupted();
      } else {
        _startTelegramBootstrap();
      }
    } catch (_) {
      // Telegram settings offers manual recovery if checkpoint loading fails.
    }
  }

  void _applyPlaybackOptions(PlaybackSettings settings) {
    _playbackOptionsRevision++;
    _playback.previousRestartSeconds = settings.previousRestartSeconds;
    if (mounted) setState(() => _artworkSwipeEnabled = settings.artworkSwipe);
  }

  Future<void> _loadPlaybackOptions() async {
    final revision = _playbackOptionsRevision;
    try {
      final settings = await PlaybackSettings.load();
      if (mounted && revision == _playbackOptionsRevision) {
        _applyPlaybackOptions(settings);
      }
    } catch (_) {
      // Keep the player's defaults when preferences are unavailable.
    }
  }

  Future<void> _startAudioService() async {
    try {
      await AudioService.init(
        builder: () => _audioHandler = PlayerAudioHandler(
          _playback,
          localLibrary: () => _loadLocalTracks(requestPermission: false),
          telegramLibrary: _loadCarTelegramPlaylists,
          playTelegram: _playCarTelegram,
        ),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.example.musicgram.playback',
          androidNotificationChannelName: 'Music playback',
          androidStopForegroundOnPause: false,
        ),
      );
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Music notification could not start.',
          kind: AppNoticeKind.error,
        );
      }
    }
    await _restoreLibrary();
  }

  void _onPlaybackChanged() {
    final playbackError = _playback.errorMessage;
    if (playbackError != null && playbackError != _lastPlaybackError) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showMessage(playbackError, kind: AppNoticeKind.error);
      });
    }
    _lastPlaybackError = playbackError;
    if (_ownsPlayback) _telegramStream.updatePrebuffer(_playback);
    if (mounted) setState(() {});
    if (!_restoring && _ownsPlayback && track != null) {
      if (_saveTimer?.isActive != true) {
        _saveTimer = Timer(const Duration(seconds: 2), _saveState);
      }
    }
  }

  Future<void> _saveState() async {
    final current = track;
    if (current == null) return;
    try {
      final file = File(
        '${(await getApplicationSupportDirectory()).path}/playback_state.json',
      );
      await file.writeAsString(
        jsonEncode({
          'path': current.path,
          'position': _playback.position.inMilliseconds,
          'volume': _playback.volume,
          'repeat': _playback.repeat,
          'shuffle': _playback.shuffle,
        }),
      );
    } catch (_) {}
  }

  Future<void> _restoreLibrary() async {
    try {
      PlaybackSettings settings;
      try {
        settings = await PlaybackSettings.load();
      } catch (_) {
        settings = PlaybackSettings();
      }
      final rows = await scanMusicLibrary();
      final tracks = rows.map((row) {
        final values = Map<String, dynamic>.from(row as Map);
        return LocalTrack(
          name: values['name'] as String,
          path: values['path'] as String,
          title: values['title'] as String?,
          artist: values['artist'] as String?,
          album: values['album'] as String?,
          genre: values['genre'] as String?,
        );
      }).toList();
      if (tracks.isEmpty || !mounted || _playback.queue.isNotEmpty) return;
      Map<String, dynamic> saved = {};
      try {
        final file = File(
          '${(await getApplicationSupportDirectory()).path}/playback_state.json',
        );
        saved = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      } catch (_) {}
      final found = tracks.indexWhere((item) => item.path == saved['path']);
      _playback.setRepeat(
        PlaybackSettings.resolve(settings.repeat, saved['repeat'] == true),
      );
      _playback.setShuffle(
        PlaybackSettings.resolve(settings.shuffle, saved['shuffle'] == true),
      );
      if (!_playback.usesSystemVolume && saved['volume'] is num) {
        await _playback.setVolume((saved['volume'] as num).toDouble());
      }
      if (_playback.queue.isNotEmpty) return;
      await _playback.loadQueue(
        tracks,
        initialIndex: found < 0 ? 0 : found,
        autoplay: false,
        allSongs: true,
      );
      if (found >= 0 && saved['position'] is int) {
        await _playback.seek(Duration(milliseconds: saved['position'] as int));
      }
      if (found >= 0 && settings.resumeOnLaunch) await _playback.play();
    } on MissingPluginException {
      // The library channel becomes available when the phone activity opens.
    } on PlatformException catch (error) {
      if (mounted) {
        _showMessage(
          error.message ?? 'Could not scan your music library.',
          kind: AppNoticeKind.error,
        );
      }
    } finally {
      _restoring = false;
    }
  }

  @override
  void dispose() {
    TelegramClient.shared.removeListener(_onProxyConnectionChanged);
    DownloadedTracks.shared.removeListener(_onDownloadStatusChanged);
    _saveTimer?.cancel();
    unawaited(_telegramStream.close());
    if (_ownsPlayback && !_restoring) _saveState();
    _playback.removeListener(_onPlaybackChanged);
    _audioHandler?.dispose();
    _telegramSheetStatus.dispose();
    if (_ownsPlayback) _playback.dispose();
    super.dispose();
  }

  Future<List<LocalTrack>> _loadLocalTracks({
    bool requestPermission = true,
  }) async {
    if (!Platform.isAndroid) {
      final files = await FilePicker.pickFiles(type: FileType.audio);
      return files
          .where((file) => file.path != null)
          .map((file) => LocalTrack(name: file.name, path: file.path!))
          .toList();
    }
    final rows = await scanMusicLibrary(requestPermission: requestPermission);
    return rows
        .map(
          (values) => LocalTrack(
            name: values['name'] as String,
            path: values['path'] as String,
            title: values['title'] as String?,
            artist: values['artist'] as String?,
            album: values['album'] as String?,
            genre: values['genre'] as String?,
          ),
        )
        .toList();
  }

  Future<void> _refreshFilteredQueue() async {
    if (!_playback.isAllSongsQueue) return;
    try {
      final tracks = await _loadLocalTracks(requestPermission: false);
      if (mounted) _playback.refreshAllSongs(tracks);
    } catch (_) {
      if (mounted) _playback.markLibraryChanged();
    }
  }

  Future<void> _openFiles({String? category}) async {
    try {
      final tracks = await _loadLocalTracks();
      if (!mounted) return;
      if (tracks.isNotEmpty || Platform.isAndroid) {
        await _openLocalSelection(tracks, category);
      }
    } on PlatformException catch (error) {
      if (mounted) {
        _showMessage(
          error.message ?? 'Could not scan your music library.',
          kind: AppNoticeKind.error,
        );
      }
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Could not open your music library.',
          kind: AppNoticeKind.error,
        );
      }
    }
  }

  Future<void> _openLocalSelection(
    List<LocalTrack> tracks,
    String? category,
  ) async {
    if (category != 'All songs') {
      if (category == null) {
        _showLocalLibrary(tracks);
      } else {
        final returnToQueue = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          backgroundColor: _surfaceColor,
          builder: (_) => LocalCategorySheet(
            category: category,
            tracks: tracks,
            onPlay: (songs, index) =>
                _playback.loadQueue(songs, initialIndex: index),
          ),
        );
        if (returnToQueue == true && mounted) _showQueue();
      }
      return;
    }
    if (tracks.isEmpty) {
      _showMessage('No music found on this device.');
      return;
    }
    final currentPath = _playback.currentTrack?.path;
    final index = tracks.indexWhere((song) => song.path == currentPath);
    final position = _playback.position;
    final playing = index >= 0 && _playback.isPlaying;
    await _playback.loadQueue(
      tracks,
      initialIndex: index < 0 ? 0 : index,
      autoplay: playing,
      allSongs: true,
    );
    if (index >= 0 && position > Duration.zero) await _playback.seek(position);
    if (mounted) _showQueue();
  }

  void _showLocalLibrary(List<LocalTrack> tracks, {String? category}) {
    var opened = false;
    final library = LocalLibraryScreen(
      tracks: tracks,
      onPlay: (songs, index) => _playback.loadQueue(songs, initialIndex: index),
      onOpenTelegram: _switchToTelegram,
      onOpenQueue: _showQueue,
    );
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (routeContext) {
          if (!opened && category != null) {
            opened = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (routeContext.mounted) {
                library.openCategory(routeContext, category);
              }
            });
          }
          return library;
        },
      ),
    );
  }

  void _switchToLocal() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    _showTrackList(
      const [],
      fromLibrary: true,
      localLibrary: true,
      localTracksFuture: _loadLocalTracks(),
    );
  }

  void _switchToTelegram() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    _startTelegramBootstrap();
    _showTrackList(_playback.queue, initialTelegram: true);
  }

  void _startTelegramBootstrap() {
    if (TelegramClient.shared.isRunning &&
        TelegramClient.shared.isAccountVerified) {
      _telegramSheetStatus.value = (state: 'ready', error: null);
    } else if (!_telegramBootstrapActive) {
      _telegramSheetStatus.value = (state: 'initializing', error: null);
      setState(() => _telegramBootstrapActive = true);
    }
  }

  Future<bool> _ensureTelegramSession() async {
    if (!mounted) return false;
    if (TelegramClient.shared.isAccountVerified &&
        TelegramClient.shared.isRunning) {
      return true;
    }
    final result = Completer<bool>();
    void check() {
      final status = _telegramSheetStatus.value;
      if (!result.isCompleted &&
          (status.state == 'ready' ||
              status.error != null ||
              !{'initializing', 'connecting'}.contains(status.state))) {
        result.complete(status.state == 'ready');
      }
    }

    _telegramSheetStatus.addListener(check);
    try {
      _startTelegramBootstrap();
      check();
      return await result.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => false,
      );
    } finally {
      _telegramSheetStatus.removeListener(check);
    }
  }

  Future<List<CarTelegramPlaylist>> _loadCarTelegramPlaylists() async {
    if (!await _ensureTelegramSession()) return [];
    final request = TelegramClient.shared.request;
    final results = <CarTelegramPlaylist>[];
    final saved = await PlaylistStore().load();
    for (var index = 0; index < saved.length; index++) {
      final playlist = saved[index];
      if (playlist['type'] != 'telegram') continue;
      final tracks = (playlist['tracks'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      results.add(
        CarTelegramPlaylist(
          id: 'saved:$index',
          title: playlist['name']?.toString() ?? 'Playlist',
          tracks: tracks,
        ),
      );
    }
    final groups = await TelegramLibraryCache(
      request: request,
      library: TelegramMusicLibrary(request: request),
    ).load(cacheOnly: true).first;
    final chats = await Future.wait(
      groups.entries.map((entry) async {
        String name = 'Telegram playlist';
        try {
          final chat = await request({'@type': 'getChat', 'chat_id': entry.key})
              .timeout(const Duration(seconds: 4));
          final title = chat['title'];
          if (title is String && title.trim().isNotEmpty) name = title;
        } catch (_) {}
        return CarTelegramPlaylist(
          id: 'chat:${entry.key}',
          title: name,
          tracks: entry.value,
        );
      }),
    );
    return [...results, ...chats];
  }

  Future<void> _playCarTelegram(
    List<Map<String, dynamic>> tracks,
    int index,
    String name,
  ) async {
    if (await _ensureTelegramSession()) {
      await _playTelegram(tracks, index, name);
    }
  }

  void _openTelegramLogin() {
    _stopTelegramBootstrap();
    Navigator.of(context).popUntil((route) => route.isFirst);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TelegramScreen(
          onBeforeSignOut: _prepareTelegramSignOut,
          onPlay: _playTelegram,
          onDownload: _downloadTelegramMessage,
          onDownloadPlaylist: _queuePlaylistDownload,
          onOpenLocal: _switchToLocal,
          openPlaylists: true,
          onOpenPlaylists: _switchToTelegram,
        ),
      ),
    );
  }

  void _stopTelegramBootstrap() {
    if (_telegramBootstrapActive && mounted) {
      setState(() => _telegramBootstrapActive = false);
    }
  }

  void _onTelegramBootstrapStatus(String state, String? error) {
    if (!mounted) return;
    _telegramSheetStatus.value = (state: state, error: error);
    if (state == 'ready') {
      unawaited(TelegramSyncJob.shared.resumeInterrupted().catchError((_) {}));
      _stopTelegramBootstrap();
    }
  }

  void _showMessage(String message, {AppNoticeKind kind = AppNoticeKind.info}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(AppSnackBar(kind: kind, content: Text(message)));
  }

  Future<void> _openTrackMetadata({required bool artist}) async {
    final current = track;
    if (current == null) return;
    final name = artist ? current.artist?.trim() : current.album?.trim();
    if (name == null || name.isEmpty || name == '<unknown>') return;

    var tracks = _playback.queue;
    if (current.telegramFileId == null && Platform.isAndroid) {
      try {
        final rows = await scanMusicLibrary();
        tracks = rows.map((row) {
          final values = Map<String, dynamic>.from(row as Map);
          return LocalTrack(
            name: values['name'] as String,
            path: values['path'] as String,
            title: values['title'] as String?,
            artist: values['artist'] as String?,
            album: values['album'] as String?,
            genre: values['genre'] as String?,
          );
        }).toList();
      } on PlatformException catch (error) {
        if (mounted) {
          _showMessage(
            error.message ?? 'Could not scan your music library.',
            kind: AppNoticeKind.error,
          );
        }
        return;
      }
    }
    final matches = tracks.where((song) {
      final value = artist ? song.artist : song.album;
      return value?.trim().toLowerCase() == name.toLowerCase();
    }).toList();
    if (!mounted) return;
    if (matches.isEmpty) {
      _showMessage('No matching songs found.');
      return;
    }
    _showTrackList(matches, fromLibrary: true, title: name);
  }

  Future<void> _openSettings() async {
    _stopTelegramBootstrap();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                child: Text(
                  'Personalize',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: Theme.of(context).colorScheme.primary),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Appearance'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openAppearance(context),
              ),
              ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: const Text('Playback'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        PlaybackSettingsScreen(onSaved: _applyPlaybackOptions),
                  ),
                ),
              ),
              if (Platform.isAndroid)
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('Notifications'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const NotificationSettingsScreen(),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                child: Text(
                  'Your music',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: Theme.of(context).colorScheme.primary),
                ),
              ),
              if (Platform.isAndroid)
                ListTile(
                  leading: const Icon(Icons.library_music_outlined),
                  title: const Text('Music library'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => MusicLibrarySettingsScreen(
                        onSaved: () => unawaited(_refreshFilteredQueue()),
                      ),
                    ),
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.playlist_play),
                title: const Text('Playlists & queue'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (settingsContext) => PlaylistQueueSettingsScreen(
                      localPlaylistsAvailable: Platform.isAndroid,
                      openPlaylists: () => Navigator.of(settingsContext).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PlaylistSettingsScreen(
                            onPlay: _playSavedPlaylist,
                            ensureTelegramSession: _ensureTelegramSession,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Downloads & cache'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DownloadSettingsScreen(
                      ensureTelegramSession: _ensureTelegramSession,
                      telegramCacheBusy: () =>
                          _playback.currentTrack?.telegramFileId != null ||
                          _pendingDownloadBatches > 0 ||
                          _pendingTelegramDownloads > 0 ||
                          _activeDownloads > 0,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                child: Text(
                  'Connections',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: Theme.of(context).colorScheme.primary),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.send_outlined),
                title: const Text('Telegram'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => TelegramScreen(
                      onBeforeSignOut: _prepareTelegramSignOut,
                      onPlay: _playTelegram,
                      onDownload: _downloadTelegramMessage,
                      onDownloadPlaylist: _queuePlaylistDownload,
                      onOpenLocal: _switchToLocal,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                child: Text(
                  'Support',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: Theme.of(context).colorScheme.primary),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Logs'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DiagnosticsLogsScreen(),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('About'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AboutDiagnosticsScreen(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await _refreshProxyState();
  }

  Future<void> _chooseThemeColor(
    BuildContext context,
    String key,
    String label,
    Color current,
  ) async {
    var colorText = (current.toARGB32() & 0xffffff)
        .toRadixString(16)
        .padLeft(6, '0')
        .toUpperCase();
    final result = await showDialog<Color>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Choose a color or enter a hex value.'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final color in [
                  Colors.white,
                  const Color(0xff101b27),
                  const Color(0xff202b39),
                  const Color(0xfff5295c),
                  const Color(0xff88c0d0),
                  const Color(0xffcba6f7),
                  const Color(0xffa6e3a1),
                  const Color(0xffffd166),
                ])
                  InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => Navigator.pop(dialogContext, color),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: colorText,
              onChanged: (value) => colorText = value,
              maxLength: 7,
              decoration: const InputDecoration(
                labelText: 'Hex color',
                prefixText: '#',
                hintText: 'F5295C',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = colorText.trim().replaceFirst(RegExp(r'^#'), '');
              if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(value)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  AppSnackBar(
                    kind: AppNoticeKind.warning,
                    content: const Text('Enter a valid six-digit hex color.'),
                  ),
                );
                return;
              }
              Navigator.pop(
                dialogContext,
                Color(0xff000000 | int.parse(value, radix: 16)),
              );
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (result != null) {
      customThemeColors.value = {
        ...customThemeColors.value,
        key: result.toARGB32(),
      };
      saveAppearance();
    }
  }

  void _openAppearance(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => StatefulBuilder(
          builder: (context, update) {
            final brightness = appThemeMode.value == ThemeMode.system
                ? MediaQuery.platformBrightnessOf(context)
                : appThemeMode.value == ThemeMode.dark
                ? Brightness.dark
                : Brightness.light;
            final prefix = brightness == Brightness.dark ? 'dark' : 'light';
            final scheme = Theme.of(context).colorScheme;
            final roles = <String, Color>{
              'background': Theme.of(context).scaffoldBackgroundColor,
              'surface': scheme.surface,
              'text': scheme.onSurface,
              'accent': scheme.primary,
            };
            final labels = <String, String>{
              'background': 'Background',
              'surface': 'Cards & surfaces',
              'text': 'Text & icons',
              'accent': 'Accent',
            };
            String name(AppPalette value) => switch (value) {
              AppPalette.gram => 'MusicGram',
              AppPalette.dracula => 'Dracula',
              AppPalette.gruvbox => 'Gruvbox',
              AppPalette.nord => 'Nord',
              AppPalette.catppuccin => 'Catppuccin',
              AppPalette.tokyo => 'Tokyo Night',
              AppPalette.solarized => 'Solarized',
              AppPalette.oneDark => 'One Dark',
            };
            List<Color> swatches(AppPalette value) => switch (value) {
              AppPalette.gram => [
                const Color(0xff101b27),
                const Color(0xff202b39),
                const Color(0xfff5295c),
              ],
              AppPalette.dracula => [
                const Color(0xff282a36),
                const Color(0xff44475a),
                const Color(0xffff79c6),
              ],
              AppPalette.gruvbox => [
                const Color(0xff282828),
                const Color(0xff3c3836),
                const Color(0xfffb4934),
              ],
              AppPalette.nord => [
                const Color(0xff2e3440),
                const Color(0xff3b4252),
                const Color(0xff88c0d0),
              ],
              AppPalette.catppuccin => [
                const Color(0xff1e1e2e),
                const Color(0xff313244),
                const Color(0xffcba6f7),
              ],
              AppPalette.tokyo => [
                const Color(0xff1a1b26),
                const Color(0xff24283b),
                const Color(0xff7aa2f7),
              ],
              AppPalette.solarized => [
                const Color(0xff002b36),
                const Color(0xff073642),
                const Color(0xff2aa198),
              ],
              AppPalette.oneDark => [
                const Color(0xff282c34),
                const Color(0xff3e4451),
                const Color(0xff61afef),
              ],
            };
            return Scaffold(
              appBar: AppBar(title: const Text('Appearance')),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                children: [
                  Text(
                    'Display mode',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: RadioGroup<ThemeMode>(
                      groupValue: appThemeMode.value,
                      onChanged: (value) {
                        if (value != null) {
                          appThemeMode.value = value;
                          saveAppearance();
                          update(() {});
                        }
                      },
                      child: const Column(
                        children: [
                          RadioListTile<ThemeMode>(
                            title: Text('Follow system'),
                            value: ThemeMode.system,
                          ),
                          RadioListTile<ThemeMode>(
                            title: Text('Dark'),
                            value: ThemeMode.dark,
                          ),
                          RadioListTile<ThemeMode>(
                            title: Text('Light'),
                            value: ThemeMode.light,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Handedness',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: RadioGroup<bool>(
                      groupValue: widget.leftHanded,
                      onChanged: (value) {
                        if (value != null) {
                          widget.onHandChanged(value);
                          update(() {});
                        }
                      },
                      child: const Column(
                        children: [
                          RadioListTile<bool>(
                            title: Text('Right-handed'),
                            value: false,
                          ),
                          RadioListTile<bool>(
                            title: Text('Left-handed'),
                            value: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Theme presets',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choosing a new preset resets custom colors.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Column(
                      children: [
                        for (final value in AppPalette.values)
                          ListTile(
                            selected: value == appPalette.value,
                            leading: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final color in swatches(value))
                                  Container(
                                    width: 16,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: color,
                                      border: Border.all(
                                        color: scheme.outlineVariant,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            title: Text(name(value)),
                            trailing: value == appPalette.value
                                ? Icon(
                                    Icons.check_circle,
                                    color: scheme.primary,
                                  )
                                : null,
                            onTap: () {
                              if (value == appPalette.value) return;
                              appPalette.value = value;
                              customAccent.value = null;
                              customThemeColors.value = {};
                              saveAppearance();
                              update(() {});
                            },
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Customize ${brightness == Brightness.dark ? 'dark' : 'light'} colors',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          final colors =
                              Map<String, int>.of(customThemeColors.value)
                                ..removeWhere(
                                  (key, _) => key.startsWith('$prefix.'),
                                );
                          customThemeColors.value = colors;
                          customAccent.value = null;
                          saveAppearance();
                          update(() {});
                        },
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                  Text(
                    'Changes apply to the current display mode.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Column(
                      children: [
                        for (final entry in roles.entries)
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: entry.value,
                              child: entry.key == 'text'
                                  ? Icon(
                                      Icons.text_fields,
                                      color: scheme.surface,
                                    )
                                  : null,
                            ),
                            title: Text(labels[entry.key]!),
                            subtitle: Text(
                              '#${(entry.value.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}',
                            ),
                            trailing: const Icon(Icons.edit_outlined),
                            onTap: () => _chooseThemeColor(
                              context,
                              '$prefix.${entry.key}',
                              labels[entry.key]!,
                              entry.value,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.leftHanded;
    return Stack(
      fit: StackFit.expand,
      children: [
        Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, viewport) {
                if (viewport.maxWidth > viewport.maxHeight) {
                  return _landscape(left);
                }
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: LayoutBuilder(
                      builder: (context, constraints) => Padding(
                        padding: const EdgeInsets.fromLTRB(10, 14, 10, 2),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.bottomCenter,
                          child: SizedBox(
                            width: constraints.maxWidth - 20,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _header(left),
                                const SizedBox(height: 14),
                                ScrollingTitle(
                                  key: ValueKey(track?.path),
                                  text: track?.displayTitle ?? 'Choose a song',
                                ),
                                Text(
                                  track == null
                                      ? 'Your local music plays offline'
                                      : track!.path.startsWith(
                                          'http://127.0.0.1:',
                                        )
                                      ? 'Telegram'
                                      : 'Local file',
                                  textAlign: left
                                      ? TextAlign.right
                                      : TextAlign.left,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: _mutedColor,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _controlArea(left),
                                _nextUp(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (_telegramBootstrapActive)
          Offstage(
            offstage: true,
            child: SizedBox(
              width: 360,
              height: 640,
              child: TickerMode(
                enabled: false,
                child: TelegramScreen(
                  onBootstrapStatus: _onTelegramBootstrapStatus,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _landscape(bool left) => Padding(
    key: const Key('landscapePlayer'),
    padding: const EdgeInsets.all(12),
    child: Stack(
      children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              textDirection: left ? TextDirection.rtl : TextDirection.ltr,
              children: [
                Expanded(
                  flex: 4,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _swipeableArtwork(),
                      if (track != null)
                        Positioned(
                          bottom: 8,
                          right: left ? null : 8,
                          left: left ? 8 : null,
                          child: _trackMenu(),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ScrollingTitle(
                        key: ValueKey(track?.path),
                        text: track?.displayTitle ?? 'Choose a song',
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => _openTrackMetadata(artist: true),
                        child: Text(
                          track?.displayArtist ?? 'Unknown artist',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: _mutedColor),
                        ),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => _openTrackMetadata(artist: false),
                        child: Text(
                          track?.album ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: _mutedColor),
                        ),
                      ),
                      const Spacer(),
                      Wrap(
                        children: [
                          TextButton.icon(
                            onPressed: () =>
                                _playback.setRepeat(!_playback.repeat),
                            icon: const Icon(Icons.repeat),
                            label: const Text('Repeat'),
                            style: TextButton.styleFrom(
                              foregroundColor: _playback.repeat
                                  ? _accentColor
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                _playback.setShuffle(!_playback.shuffle),
                            icon: const Icon(Icons.shuffle),
                            label: const Text('Shuffle'),
                            style: TextButton.styleFrom(
                              foregroundColor: _playback.shuffle
                                  ? _accentColor
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      _nextUp(),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 3,
                  child: Align(
                    alignment: left
                        ? Alignment.bottomLeft
                        : Alignment.bottomRight,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      alignment: left
                          ? Alignment.bottomLeft
                          : Alignment.bottomRight,
                      child: SizedBox(
                        width: 300,
                        height: 300,
                        child: _landscapeControls(left),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_proxyEnabled)
          Positioned(
            top: 64,
            right: 8,
            child: IconButton.filled(
              key: const Key('proxyShortcut'),
              tooltip: 'Proxy settings',
              style: IconButton.styleFrom(backgroundColor: _accentColor),
              onPressed: _openProxyList,
              icon: _proxyIcon(),
            ),
          ),
        Positioned(
          top: 8,
          right: 8,
          child: IconButton.filled(
            key: const Key('settingsButton'),
            tooltip: 'Settings',
            style: IconButton.styleFrom(backgroundColor: _accentColor),
            onPressed: _openSettings,
            icon: const Icon(Icons.settings),
          ),
        ),
      ],
    ),
  );

  Widget _landscapeControls(bool left) => SizedBox(
    height: 300,
    child: Stack(
      children: [
        Positioned(
          left: left ? 0 : null,
          right: left ? null : 0,
          top: 0,
          child: IgnorePointer(
            ignoring: _playback.isCasting && !_playback.canControlCastVolume,
            child: Opacity(
              opacity: _playback.isCasting && !_playback.canControlCastVolume
                  ? 0.4
                  : 1,
              child: ArcVolumeSlider(
                value: _playback.volume,
                leftHanded: left,
                onChanged: _playback.setVolume,
              ),
            ),
          ),
        ),
        Positioned(
          left: left ? 8 : null,
          right: left ? null : 8,
          top: 60,
          child: _roundButton(
            Icons.play_arrow_rounded,
            _playback.showPauseControl ? 'Pause playback' : 'Play playback',
            72,
            track == null ? _openFiles : _playback.togglePlayback,
            icon: _playback.showPauseControl
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            color: _accentColor,
          ),
        ),
        Positioned(
          left: left ? 110 : null,
          right: left ? null : 110,
          top: 135,
          child: _roundButton(
            Icons.skip_next_rounded,
            'Next track',
            58,
            track == null ? null : _playback.next,
          ),
        ),
        Positioned(
          left: left ? 125 : null,
          right: left ? null : 125,
          top: 225,
          child: _roundButton(
            Icons.skip_previous_rounded,
            'Previous track',
            58,
            track == null ? null : _playback.previous,
          ),
        ),
        Positioned(
          left: left ? 8 : null,
          right: left ? null : 8,
          top: 180,
          child: _timer(),
        ),
      ],
    ),
  );

  Future<Uint8List?> _artFor(LocalTrack song) =>
      EmbeddedArtwork.load(song.path);

  Widget _cover(LocalTrack? song, {double? size}) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: SizedBox(
      width: size,
      height: size,
      child: song == null
          ? ColoredBox(
              color: _surfaceColor,
              child: Icon(Icons.music_note, color: _mutedColor),
            )
          : FutureBuilder<Uint8List?>(
              key: ValueKey(song.path),
              future: _artFor(song),
              builder: (context, snapshot) => snapshot.data == null
                  ? _generatedCover(song)
                  : Image.memory(
                      snapshot.data!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          Icon(Icons.music_note, color: _mutedColor),
                    ),
            ),
    ),
  );

  Widget _generatedCover(LocalTrack song) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: generatedArtworkColors(song.path),
        ),
      ),
      child: const Center(
        child: Icon(Icons.music_note_rounded, color: Colors.white70),
      ),
    );
  }

  Widget _swipeableArtwork() => _ArtworkCarousel(
    enabled: _artworkSwipeEnabled,
    track: track,
    previous: _playback.queue.length < 2
        ? track
        : _playback.queue[(_playback.currentIndex -
                  1 +
                  _playback.queue.length) %
              _playback.queue.length],
    next: _playback.nextIndex == null
        ? track
        : _playback.queue[_playback.nextIndex!],
    coverBuilder: _cover,
    onNext: _playback.next,
    onPrevious: () => _playback.previous(restartCurrent: false),
  );

  Widget _header(bool left) => SizedBox(
    key: const Key('artworkHeader'),
    height: 340,
    child: Stack(
      children: [
        Positioned.fill(child: _swipeableArtwork()),
        if (_proxyEnabled)
          Positioned(
            top: 64,
            right: left ? null : 8,
            left: left ? 8 : null,
            child: IconButton.filled(
              key: const Key('proxyShortcut'),
              tooltip: 'Proxy settings',
              style: IconButton.styleFrom(backgroundColor: _accentColor),
              onPressed: _openProxyList,
              icon: _proxyIcon(),
            ),
          ),
        if (track != null)
          Positioned(
            bottom: 8,
            right: left ? null : 8,
            left: left ? 8 : null,
            child: _trackMenu(),
          ),
        Positioned(
          top: 8,
          right: left ? null : 8,
          left: left ? 8 : null,
          child: IconButton.filled(
            key: const Key('settingsButton'),
            tooltip: 'Settings',
            style: IconButton.styleFrom(backgroundColor: _accentColor),
            onPressed: _openSettings,
            icon: const Icon(Icons.settings),
          ),
        ),
      ],
    ),
  );

  Widget _metadata(bool left) => Align(
    alignment: left ? Alignment.centerRight : Alignment.centerLeft,
    child: Column(
      crossAxisAlignment: left
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        _infoChip(
          Icons.person_outline,
          track?.displayArtist ?? 'Artist',
          () => _openTrackMetadata(artist: true),
        ),
        const SizedBox(height: 7),
        _infoChip(
          Icons.album_outlined,
          track?.album?.isNotEmpty == true ? track!.album! : 'Album',
          () => _openTrackMetadata(artist: false),
        ),
      ],
    ),
  );

  Widget _infoChip(IconData icon, String text, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 10),
          Flexible(
            child: ScrollingTitle(
              key: ValueKey(text),
              text: text,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right, color: _mutedColor),
        ],
      ),
    ),
  );

  Widget _controlArea(bool left) => SizedBox(
    height: 270,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final side = left ? -20.0 : null;
        final opposite = left ? null : -20.0;
        return Stack(
          children: [
            Positioned(
              left: side,
              right: opposite,
              top: -30,
              child: IgnorePointer(
                ignoring:
                    _playback.isCasting && !_playback.canControlCastVolume,
                child: Opacity(
                  opacity:
                      _playback.isCasting && !_playback.canControlCastVolume
                      ? 0.4
                      : 1,
                  child: ArcVolumeSlider(
                    key: const Key('volumeArc'),
                    value: _playback.volume,
                    leftHanded: left,
                    onChanged: _playback.setVolume,
                  ),
                ),
              ),
            ),
            Positioned(
              left: left ? null : 2,
              right: left ? 2 : null,
              top: 6,
              width: (constraints.maxWidth - 205).clamp(80.0, 230.0),
              child: _metadata(left),
            ),
            Positioned(
              left: left ? 8 : null,
              right: left ? null : 8,
              top: 48,
              child: _roundButton(
                Icons.play_arrow_rounded,
                track == null
                    ? 'Choose music files'
                    : _playback.showPauseControl
                    ? 'Pause playback'
                    : 'Play playback',
                72,
                track == null ? _openFiles : _playback.togglePlayback,
                icon: _playback.showPauseControl
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: _accentColor,
              ),
            ),
            Positioned(
              left: left ? 110 : null,
              right: left ? null : 110,
              top: 113,
              child: _roundButton(
                Icons.skip_next_rounded,
                'Next track',
                58,
                track == null ? null : _playback.next,
              ),
            ),
            Positioned(
              left: left ? 125 : null,
              right: left ? null : 125,
              top: 202,
              child: _roundButton(
                Icons.skip_previous_rounded,
                'Previous track',
                58,
                track == null ? null : _playback.previous,
              ),
            ),
            Positioned(
              left: left ? 8 : null,
              right: left ? null : 8,
              top: 160,
              child: _timer(),
            ),
            Positioned(
              left: left ? null : 2,
              right: left ? 2 : null,
              bottom: 0,
              child: Column(
                crossAxisAlignment: left
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  TextButton.icon(
                    onPressed: () => _playback.setRepeat(!_playback.repeat),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: _playback.repeat
                          ? _accentColor
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                    icon: AnimatedRotation(
                      turns: _playback.repeat ? .5 : 0,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                      child: const Icon(Icons.repeat),
                    ),
                    label: const Text('Repeat'),
                  ),
                  TextButton.icon(
                    onPressed: () => _playback.setShuffle(!_playback.shuffle),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: _playback.shuffle
                          ? _accentColor
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                    icon: AnimatedRotation(
                      turns: _playback.shuffle ? .5 : 0,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                      child: const Icon(Icons.shuffle),
                    ),
                    label: const Text('Shuffle'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _roundButton(
    IconData fallback,
    String tooltip,
    double diameter,
    VoidCallback? onPressed, {
    IconData? icon,
    Color color = const Color(0xFF485465),
  }) => SizedBox.square(
    dimension: diameter,
    child: IconButton.filled(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(backgroundColor: color),
      iconSize: diameter * .46,
      icon: Icon(icon ?? fallback),
    ),
  );

  Widget _timer() {
    final durationMs = _playback.duration.inMilliseconds;
    final remainingSeconds = math.max(
      0,
      _playback.duration.inSeconds - _playback.position.inSeconds,
    );
    final progress = durationMs <= 0
        ? 0.0
        : (_playback.position.inMilliseconds / durationMs).clamp(0.0, 1.0);
    void seekAt(Offset point) {
      if (track == null || durationMs <= 0) return;
      final angle = math.atan2(point.dy - 52, point.dx - 52);
      final fraction = ((angle + math.pi / 2) % (2 * math.pi)) / (2 * math.pi);
      _playback.seek(Duration(milliseconds: (durationMs * fraction).round()));
    }

    return GestureDetector(
      key: const Key('circularSeek'),
      onTapDown: (details) => seekAt(details.localPosition),
      onPanUpdate: (details) => seekAt(details.localPosition),
      child: SizedBox.square(
        dimension: 104,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.square(
              dimension: 104,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 3,
                backgroundColor: _mutedColor,
                color: _accentColor,
              ),
            ),
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [_accentColor, _accentColor.withValues(alpha: .45)],
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _RotatingRecord(isPlaying: _playback.isPlaying),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _formatTime(_playback.position),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '-${_formatTime(Duration(seconds: remainingSeconds))}',
                        style: TextStyle(color: _mutedColor, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(Duration value) {
    final minutes = value.inMinutes.toString().padLeft(2, '0');
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _nextUp() => GestureDetector(
    onTap: () {
      if (Platform.isAndroid &&
          QueueShortcutSettings.openingView.value == 'playlists') {
        _showTrackList(
          _playback.queue,
          initialLocalCategory: 'Playlists',
          localTracksFuture: _loadLocalTracks(),
        );
      } else {
        _showQueue();
      }
    },
    child: Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          _cover(
            _playback.nextIndex == null
                ? null
                : _playback.queue[_playback.nextIndex!],
            size: 60,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Next up',
                  style: TextStyle(color: _mutedColor, fontSize: 12),
                ),
                Text(
                  _playback.nextIndex != null
                      ? _playback.queue[_playback.nextIndex!].displayTitle
                      : _playback.queue.isEmpty
                      ? 'Choose local music'
                      : 'End of queue',
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _trackMenu() => PopupMenuButton<String>(
    tooltip: 'Current track actions',
    icon: const Icon(Icons.menu),
    style: IconButton.styleFrom(backgroundColor: _accentColor),
    onSelected: (action) {
      final song = track;
      if (song == null) return;
      switch (action) {
        case 'playlist':
          _addCurrentToPlaylist(song);
        case 'download':
          _downloadTelegram(song);
        case 'info':
          _showTrackInfo(song);
        case 'lyrics':
          _showLyrics();
        case 'upnp':
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => UpnpDiscoveryScreen(player: _playback),
            ),
          );
      }
    },
    itemBuilder: (context) => [
      const PopupMenuItem(
        value: 'playlist',
        child: ListTile(
          leading: Icon(Icons.playlist_add),
          title: Text('Add to playlist'),
        ),
      ),
      if (track!.telegramFileId != null &&
          !DownloadedTracks.shared.contains(track!.downloadKey))
        const PopupMenuItem(
          value: 'download',
          child: ListTile(
            leading: Icon(Icons.download_outlined),
            title: Text('Download track'),
          ),
        ),
      const PopupMenuItem(
        value: 'lyrics',
        child: ListTile(
          leading: Icon(Icons.lyrics_outlined),
          title: Text('Lyrics'),
        ),
      ),
      const PopupMenuItem(
        value: 'info',
        child: ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Music info'),
        ),
      ),
      const PopupMenuItem(
        value: 'upnp',
        child: ListTile(
          leading: Icon(Icons.cast),
          title: Text('Cast to device'),
        ),
      ),
    ],
  );

  void _showLyrics() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      clipBehavior: Clip.antiAlias,
      builder: (context) {
        final screen = MediaQuery.sizeOf(context).height;
        final keyboard = MediaQuery.viewInsetsOf(context).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: SizedBox(
            height: (screen * .88 - keyboard).clamp(180.0, screen),
            child: LyricsSheet(player: _playback),
          ),
        );
      },
    );
  }

  void _showQueue() => _showTrackList(_playback.queue);

  void _showTrackList(
    List<LocalTrack> tracks, {
    bool fromLibrary = false,
    String? title,
    bool localLibrary = false,
    Future<List<LocalTrack>>? localTracksFuture,
    bool initialTelegram = false,
    String? initialLocalCategory,
  }) {
    var search = '';
    var showingTelegram = initialTelegram;
    var telegramCategory = 'All songs';
    String? localCategory = initialLocalCategory;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surfaceColor,
      isScrollControlled: true,
      clipBehavior: Clip.antiAlias,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          if (showingTelegram) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SafeArea(
                child: SizedBox(
                  height:
                      (MediaQuery.sizeOf(context).height * .8 -
                              MediaQuery.viewInsetsOf(context).bottom)
                          .clamp(200.0, double.infinity),
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('Telegram'),
                        trailing: TextButton.icon(
                          icon: const Icon(Icons.library_music_outlined),
                          label: const Text('Local'),
                          onPressed: () => update(() {
                            showingTelegram = false;
                            localCategory = null;
                            if (track?.telegramFileId != null || localLibrary) {
                              fromLibrary = true;
                              localLibrary = true;
                              localTracksFuture ??= _loadLocalTracks();
                            }
                            search = '';
                          }),
                        ),
                      ),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            for (final category
                                in QueueShortcutSettings.order.value)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ActionChip(
                                  label: Text(category),
                                  side: category == telegramCategory
                                      ? BorderSide(
                                          color: _accentColor,
                                          width: 2,
                                        )
                                      : null,
                                  backgroundColor: category == telegramCategory
                                      ? _accentColor.withValues(alpha: .15)
                                      : null,
                                  onPressed: category == telegramCategory
                                      ? () {}
                                      : () => update(
                                          () => telegramCategory = category,
                                        ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: TelegramLibrarySheet(
                          status: _telegramSheetStatus,
                          category: telegramCategory,
                          hideHeader: true,
                          onBack: () => update(() {
                            showingTelegram = false;
                            search = '';
                          }),
                          onPlay: _playTelegram,
                          onDownload: _downloadTelegramMessage,
                          onDownloadPlaylist: _queuePlaylistDownload,
                          onOpenTelegramSettings: _openTelegramLogin,
                          onOpenLocal: () {
                            update(() {
                              showingTelegram = false;
                              search = '';
                              if (track?.telegramFileId != null ||
                                  localLibrary) {
                                fromLibrary = true;
                                localLibrary = true;
                                localTracksFuture ??= _loadLocalTracks();
                              }
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          return FutureBuilder<List<LocalTrack>>(
            future: localTracksFuture,
            builder: (context, localSnapshot) => AnimatedBuilder(
              animation: _playback,
              builder: (context, _) {
                final loadingLocal =
                    localTracksFuture != null &&
                    localSnapshot.connectionState != ConnectionState.done;
                final visibleTracks = fromLibrary
                    ? (localTracksFuture == null
                          ? tracks
                          : localSnapshot.data ?? const <LocalTrack>[])
                    : _playback.queue;
                final telegramQueue =
                    !localLibrary &&
                    !fromLibrary &&
                    track?.telegramFileId != null;
                final indices = List<int>.generate(visibleTracks.length, (i) => i)
                    .where(
                      (i) => librarySearchMatches(
                        '${visibleTracks[i].displayTitle} ${visibleTracks[i].displayArtist}',
                        search,
                      ),
                    )
                    .toList();
                if (localCategory != null) {
                  final sheetHeight =
                      (MediaQuery.sizeOf(context).height * .8 -
                              MediaQuery.viewInsetsOf(context).bottom)
                          .clamp(200.0, double.infinity);
                  return SafeArea(
                    child: loadingLocal
                        ? SizedBox(
                            height: sheetHeight,
                            child: const LibraryLoadingSkeleton(),
                          )
                        : localSnapshot.hasError
                        ? SizedBox(
                            height: sheetHeight,
                            child: const Center(
                              child: Text('Could not load local music.'),
                            ),
                          )
                        : LocalCategorySheet(
                            key: ValueKey(localCategory),
                            category: localCategory!,
                            tracks: localSnapshot.data ?? const [],
                            onBack: () => update(() => localCategory = null),
                            onPlay: (songs, index) =>
                                _playback.loadQueue(songs, initialIndex: index),
                          ),
                  );
                }
                return SafeArea(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.viewInsetsOf(context).bottom,
                    ),
                    child: SizedBox(
                      height:
                          (MediaQuery.sizeOf(context).height * .8 -
                                  MediaQuery.viewInsetsOf(context).bottom)
                              .clamp(200.0, double.infinity),
                      child: Column(
                        children: [
                          ListTile(
                            title: Text(title ?? 'Current queue'),
                            trailing: title != null
                                ? null
                                : TextButton.icon(
                                    icon: Icon(
                                      !localLibrary &&
                                              track?.telegramFileId != null
                                          ? Icons.library_music_outlined
                                          : Icons.send_outlined,
                                    ),
                                    label: Text(
                                      !localLibrary &&
                                              track?.telegramFileId != null
                                          ? 'Local'
                                          : 'Telegram',
                                    ),
                                    onPressed: () {
                                      if (!localLibrary &&
                                          track?.telegramFileId != null) {
                                        update(() {
                                          fromLibrary = true;
                                          localLibrary = true;
                                          localTracksFuture ??=
                                              _loadLocalTracks();
                                          search = '';
                                        });
                                      } else {
                                        FocusManager.instance.primaryFocus
                                            ?.unfocus();
                                        _startTelegramBootstrap();
                                        update(() {
                                          showingTelegram = true;
                                          telegramCategory = 'All songs';
                                          search = '';
                                        });
                                      }
                                    },
                                  ),
                          ),
                          if (title == null)
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Row(
                                children: [
                                  for (final category
                                      in QueueShortcutSettings.order.value)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ActionChip(
                                        label: Text(category),
                                        side:
                                            !telegramQueue &&
                                                category == 'All songs' &&
                                                _playback.isAllSongsQueue
                                            ? BorderSide(
                                                color: _accentColor,
                                                width: 2,
                                              )
                                            : null,
                                        backgroundColor:
                                            !telegramQueue &&
                                                category == 'All songs' &&
                                                _playback.isAllSongsQueue
                                            ? _accentColor.withValues(
                                                alpha: .15,
                                              )
                                            : null,
                                        onPressed:
                                            !telegramQueue &&
                                                category == 'All songs' &&
                                                _playback.isAllSongsQueue
                                            ? () {}
                                            : () {
                                                if (telegramQueue) {
                                                  FocusManager
                                                      .instance
                                                      .primaryFocus
                                                      ?.unfocus();
                                                  _startTelegramBootstrap();
                                                  update(() {
                                                    showingTelegram = true;
                                                    telegramCategory = category;
                                                    search = '';
                                                  });
                                                  return;
                                                }
                                                if (category == 'All songs') {
                                                  Navigator.pop(context);
                                                  _openFiles(
                                                    category: category,
                                                  );
                                                } else {
                                                  update(() {
                                                    localTracksFuture ??=
                                                        _loadLocalTracks();
                                                    localCategory = category;
                                                  });
                                                }
                                              },
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          Expanded(
                            child: loadingLocal
                                ? const LibraryLoadingSkeleton()
                                : localSnapshot.hasError
                                ? const Center(
                                    child: Text(
                                      'Could not load local music. Reopen the list to try again.',
                                    ),
                                  )
                                : localTracksFuture != null &&
                                      visibleTracks.isEmpty
                                ? const Center(
                                    child: Text('No local music found.'),
                                  )
                                : ListView.builder(
                                    itemCount: indices.length,
                                    itemBuilder: (context, position) {
                                      final index = indices[position];
                                      final song = visibleTracks[index];
                                      return ListTile(
                                        leading: _cover(song, size: 48),
                                        title: Text(
                                          song.displayTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color:
                                                (fromLibrary
                                                    ? song.path == track?.path
                                                    : index ==
                                                          _playback
                                                              .currentIndex)
                                                ? _accentColor
                                                : null,
                                          ),
                                        ),
                                        subtitle: Text(
                                          song.displayArtist,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        trailing: song.telegramFileId == null
                                            ? null
                                            : ListenableBuilder(
                                                listenable:
                                                    DownloadedTracks.shared,
                                                builder: (context, _) =>
                                                    DownloadedTracks.shared
                                                        .contains(
                                                          song.downloadKey,
                                                        )
                                                    ? const SizedBox.shrink()
                                                    : IconButton(
                                                        tooltip:
                                                            'Download track',
                                                        icon: const Icon(
                                                          Icons
                                                              .download_outlined,
                                                        ),
                                                        onPressed: () =>
                                                            _downloadTelegram(
                                                              song,
                                                            ),
                                                      ),
                                              ),
                                        onTap: () {
                                          Navigator.pop(context);
                                          if (fromLibrary) {
                                            _playback.loadQueue(
                                              visibleTracks,
                                              initialIndex: index,
                                              allSongs: localLibrary,
                                            );
                                          } else {
                                            _playback.playTrackAt(index);
                                          }
                                        },
                                      );
                                    },
                                  ),
                          ),
                          LibrarySearch(
                            hint: 'Search songs or artists',
                            onChanged: (value) => update(() => search = value),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _RotatingRecord extends StatefulWidget {
  const _RotatingRecord({required this.isPlaying});
  final bool isPlaying;
  @override
  State<_RotatingRecord> createState() => _RotatingRecordState();
}

class _RotatingRecordState extends State<_RotatingRecord>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );
  @override
  void initState() {
    super.initState();
    if (widget.isPlaying) controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _RotatingRecord oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        controller.repeat();
      } else {
        controller.stop();
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RotationTransition(
      turns: controller,
      child: Opacity(
        opacity: .38,
        child: Image.asset(
          'assets/images/record.png',
          width: 92,
          height: 92,
          fit: BoxFit.contain,
        ),
      ),
    ),
  );
}

class _ArtworkCarousel extends StatefulWidget {
  const _ArtworkCarousel({
    required this.track,
    required this.previous,
    required this.next,
    required this.coverBuilder,
    required this.onNext,
    required this.onPrevious,
    required this.enabled,
  });

  final LocalTrack? track;
  final LocalTrack? previous;
  final LocalTrack? next;
  final Widget Function(LocalTrack?) coverBuilder;
  final Future<void> Function() onNext;
  final Future<void> Function() onPrevious;
  final bool enabled;

  @override
  State<_ArtworkCarousel> createState() => _ArtworkCarouselState();
}

class _ArtworkCarouselState extends State<_ArtworkCarousel> {
  static const initialPage = 10000;
  final PageController controller = PageController(initialPage: initialPage);
  int currentPage = initialPage;
  String? dragTrack;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      dragTrack = widget.track?.path;
    }
    if (notification is ScrollEndNotification && controller.hasClients) {
      final page = controller.page?.round() ?? currentPage;
      final trackUnchanged =
          dragTrack != null && dragTrack == widget.track?.path;
      dragTrack = null;
      if (trackUnchanged && page != currentPage) {
        final next = page > currentPage;
        setState(() => currentPage = page);
        if (next) {
          widget.onNext();
        } else {
          widget.onPrevious();
        }
      } else if (page != currentPage) {
        setState(() => currentPage = page);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: PageView.builder(
        key: const Key('swipeableArtwork'),
        physics: widget.enabled ? null : const NeverScrollableScrollPhysics(),
        controller: controller,
        itemBuilder: (context, index) => widget.coverBuilder(
          index < currentPage
              ? widget.previous
              : index > currentPage
              ? widget.next
              : widget.track,
        ),
      ),
    ),
  );
}

class ScrollingTitle extends StatefulWidget {
  const ScrollingTitle({
    super.key,
    required this.text,
    this.style = const TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
  });
  final String text;
  final TextStyle style;
  @override
  State<ScrollingTitle> createState() => _ScrollingTitleState();
}

class _ScrollingTitleState extends State<ScrollingTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat(reverse: true);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    return LayoutBuilder(
      builder: (context, constraints) {
        final lineHeight = TextPainter(
          text: TextSpan(text: 'Ag گپ', style: style),
          textScaler: MediaQuery.textScalerOf(context),
          textDirection: Directionality.of(context),
        )..layout();
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout();
        final overflow = (painter.width - constraints.maxWidth).clamp(
          0.0,
          double.infinity,
        );
        return ClipRect(
          child: SizedBox(
            height: lineHeight.height + 6,
            child: Center(
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, child) => Transform.translate(
                  offset: Offset(-overflow * controller.value, 0),
                  child: child,
                ),
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  maxWidth: double.infinity,
                  child: Text(widget.text, maxLines: 1, style: style),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class CarTelegramPlaylist {
  const CarTelegramPlaylist({
    required this.id,
    required this.title,
    required this.tracks,
  });
  final String id;
  final String title;
  final List<Map<String, dynamic>> tracks;
}

class PlayerAudioHandler extends BaseAudioHandler with SeekHandler {
  PlayerAudioHandler(
    this.player, {
    TelegramRequest? telegramRequest,
    this.localLibrary,
    this.telegramLibrary,
    this.playTelegram,
    Future<Uri?> Function(String path)? shareArtwork,
    Future<String> Function(LocalTrack track)? generateArtwork,
  }) : _generateArtwork =
           generateArtwork ?? ((track) => saveGeneratedArtwork(track.path)),
       _telegramRequest = telegramRequest ?? TelegramClient.shared.request,
       _shareArtwork = shareArtwork ?? _shareArtworkWithAndroid {
    player.addListener(_publish);
    NotificationSettings.showArtwork.addListener(_artworkSettingChanged);
    NotificationSettings.showCompactSkip.addListener(_publish);
    _publish();
  }
  final PlaybackController player;
  final TelegramRequest _telegramRequest;
  final Future<Uri?> Function(String path) _shareArtwork;
  final Future<String> Function(LocalTrack track) _generateArtwork;

  static Future<Uri?> _shareArtworkWithAndroid(String path) async {
    if (!Platform.isAndroid) return Uri.file(path);
    final value = await const MethodChannel('musicgram/library')
        .invokeMethod<String>('shareArtwork', {'path': path});
    return value == null ? null : Uri.tryParse(value);
  }

  final Future<List<LocalTrack>> Function()? localLibrary;
  final Future<List<CarTelegramPlaylist>> Function()? telegramLibrary;
  final Future<void> Function(List<Map<String, dynamic>>, int, String)?
  playTelegram;
  final Map<String, CarTelegramPlaylist> _carTelegramPlaylists = {};
  List<LocalTrack> _carLocalTracks = const [];

  MediaItem _carTrack(LocalTrack track, String source) => MediaItem(
    id: '$source:${Uri.encodeComponent(track.path)}',
    title: track.displayTitle,
    artist: track.displayArtist,
    album: track.album,
  );

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    if (parentMediaId == AudioService.browsableRootId) {
      return const [
        MediaItem(id: 'car:queue', title: 'Current queue', playable: false),
        MediaItem(id: 'car:local', title: 'All songs', playable: false),
        MediaItem(id: 'car:telegram', title: 'Telegram', playable: false),
      ];
    }
    if (parentMediaId == 'car:queue') {
      return player.queue.map((track) => _carTrack(track, 'queue')).toList();
    }
    if (parentMediaId == 'car:telegram' && telegramLibrary != null) {
      try {
        final playlists = await telegramLibrary!();
        _carTelegramPlaylists
          ..clear()
          ..addEntries(
            playlists.map((playlist) => MapEntry(playlist.id, playlist)),
          );
        return playlists
            .map(
              (playlist) => MediaItem(
                id: 'tgplaylist:${Uri.encodeComponent(playlist.id)}',
                title: playlist.title,
                playable: false,
              ),
            )
            .toList();
      } catch (_) {
        return [];
      }
    }
    if (parentMediaId.startsWith('tgplaylist:')) {
      final id = Uri.decodeComponent(
        parentMediaId.substring('tgplaylist:'.length),
      );
      final playlist = _carTelegramPlaylists[id];
      if (playlist == null) return [];
      return [
        for (var index = 0; index < playlist.tracks.length; index++)
          if (playlist.tracks[index]['content'] is Map)
            _carTelegramTrack(playlist, index),
      ];
    }
    if (parentMediaId == 'car:local' && localLibrary != null) {
      try {
        _carLocalTracks = await localLibrary!();
      } catch (_) {
        _carLocalTracks = const [];
      }
      return _carLocalTracks.map((track) => _carTrack(track, 'local')).toList();
    }
    return const [];
  }

  MediaItem _carTelegramTrack(CarTelegramPlaylist playlist, int index) {
    final content = playlist.tracks[index]['content'] as Map;
    final media = content['audio'] ?? content['document'];
    final data = media is Map ? media : const {};
    final title = data['title'];
    final filename = data['file_name'];
    return MediaItem(
      id: 'tgtrack:${Uri.encodeComponent(playlist.id)}:$index',
      title: title is String && title.trim().isNotEmpty
          ? title
          : filename is String && filename.trim().isNotEmpty
          ? filename
          : 'Telegram track',
      artist: data['performer'] is String ? data['performer'] as String : null,
    );
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    final separator = mediaId.indexOf(':');
    if (separator < 0) return;
    final source = mediaId.substring(0, separator);
    final String path;
    try {
      path = Uri.decodeComponent(mediaId.substring(separator + 1));
    } on FormatException {
      return;
    }
    if (source == 'queue') {
      final index = player.queue.indexWhere((track) => track.path == path);
      if (index >= 0) await player.playTrackAt(index);
    } else if (source == 'local') {
      final index = _carLocalTracks.indexWhere((track) => track.path == path);
      if (index >= 0) {
        await player.loadQueue(
          _carLocalTracks,
          initialIndex: index,
          allSongs: true,
        );
      }
    } else if (source == 'tgtrack') {
      final split = mediaId.lastIndexOf(':');
      if (split <= separator) return;
      final id = Uri.decodeComponent(mediaId.substring(separator + 1, split));
      final index = int.tryParse(mediaId.substring(split + 1));
      final playlist = _carTelegramPlaylists[id];
      if (playlist != null &&
          index != null &&
          index >= 0 &&
          index < playlist.tracks.length) {
        await playTelegram?.call(playlist.tracks, index, playlist.title);
      }
    }
  }

  String? _lastMediaPath;
  Duration? _lastMediaDuration;
  String? _artTrack;
  Uri? _artUri;
  int _artGeneration = 0;

  void _artworkSettingChanged() {
    _artTrack = null;
    _artUri = null;
    _artGeneration++;
    _lastMediaPath = null;
    _publish();
  }

  Future<void> _loadArtwork(LocalTrack track, int generation) async {
    bool current() =>
        generation == _artGeneration &&
        NotificationSettings.showArtwork.value &&
        player.currentTrack?.path == track.path;
    try {
      String? path;
      try {
        if (track.telegramMessage != null) {
          path = await resolveTelegramArtwork(
            track.telegramMessage!,
            _telegramRequest,
          );
        } else if (Platform.isAndroid) {
          final bytes = await const MethodChannel('musicgram/library')
              .invokeMethod<Uint8List>('artwork', {'path': track.path});
          if (bytes != null && bytes.isNotEmpty) {
            final directory = await getTemporaryDirectory();
            final file = File(
              '${directory.path}/notification_art_${track.path.hashCode}.img',
            );
            await file.writeAsBytes(bytes, flush: true);
            path = file.path;
          }
        }
      } catch (_) {
        // A missing or inaccessible cover falls back to generated artwork.
      }
      if (!current()) return;
      Uri? uri;
      if (path != null) {
        try {
          uri = await _shareArtwork(path);
        } catch (_) {
          // Try the generated cover if the original image cannot be shared.
        }
      }
      if (!current()) return;
      if (uri == null) {
        path = await _generateArtwork(track);
        if (!current()) return;
        uri = await _shareArtwork(path);
      }
      if (!current()) return;
      _artUri = uri;
      _lastMediaPath = null;
      _publish();
    } catch (_) {
      // Playback remains available when artwork cannot be generated or shared.
    }
  }

  void _publish() {
    final track = player.currentTrack;
    if (track != null && track.path != _artTrack) {
      _artTrack = track.path;
      _artUri = null;
      final generation = ++_artGeneration;
      if (NotificationSettings.showArtwork.value) {
        unawaited(_loadArtwork(track, generation));
      }
    }
    if (track != null &&
        (track.path != _lastMediaPath ||
            player.duration != _lastMediaDuration)) {
      _lastMediaPath = track.path;
      _lastMediaDuration = player.duration;
      mediaItem.add(
        MediaItem(
          id: track.path,
          title: track.displayTitle,
          artist: track.displayArtist,
          album: track.album,
          artUri: _artUri,
          duration: player.duration,
        ),
      );
    }
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          player.isPlaying ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        androidCompactActionIndices: NotificationSettings.showCompactSkip.value
            ? const [0, 1, 2]
            : const [1],
        systemActions: const {MediaAction.seek},
        processingState: player.isLoading
            ? AudioProcessingState.loading
            : track == null
            ? AudioProcessingState.idle
            : AudioProcessingState.ready,
        playing: player.isPlaying,
        updatePosition: player.position,
      ),
    );
  }

  @override
  Future<void> play() => player.play();
  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> skipToNext() => player.next();
  @override
  Future<void> skipToPrevious() => player.previous();
  @override
  Future<void> seek(Duration position) => player.seek(position);
  @override
  Future<void> stop() async {
    await player.pause();
    await super.stop();
  }

  void dispose() {
    _artGeneration++;
    player.removeListener(_publish);
    NotificationSettings.showArtwork.removeListener(_artworkSettingChanged);
    NotificationSettings.showCompactSkip.removeListener(_publish);
  }
}
