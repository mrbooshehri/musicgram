import 'package:flutter/material.dart';

import 'app_snack_bar.dart';

import 'dart:io';

import 'telegram_client.dart';
import 'telegram_music_library.dart';
import 'telegram_library_cache.dart';
import 'telegram_artwork.dart';
import 'telegram_playback_log.dart';
import 'downloaded_tracks.dart';
import 'playlist_store.dart';
import 'playlist_cover.dart';
import 'loading_skeleton.dart';
import 'library_search.dart';
import 'telegram_sync_job.dart';
import 'error_toast_notice.dart';

class TelegramPlaylistsScreen extends StatefulWidget {
  const TelegramPlaylistsScreen({
    super.key,
    this.library,
    this.request,
    this.cacheDirectory,
    this.onPlay,
    this.onDownload,
    this.onDownloadPlaylist,
    this.onOpenLocal,
    this.sheetMode = false,
    this.initialRefresh = false,
    this.category = 'Playlists',
    this.hideHeader = false,
    this.onCategoryBack,
  });

  final TelegramMusicLibrary? library;
  final TelegramRequest? request;
  final Future<Directory> Function()? cacheDirectory;
  final Future<void> Function(List<Map<String, dynamic>>, int, String)? onPlay;
  final Future<void> Function(Map<String, dynamic>, String)? onDownload;
  final void Function(List<Map<String, dynamic>>, String)? onDownloadPlaylist;
  final VoidCallback? onOpenLocal;
  final bool sheetMode;
  final bool initialRefresh;
  final String category;
  final bool hideHeader;
  final VoidCallback? onCategoryBack;

  @override
  State<TelegramPlaylistsScreen> createState() =>
      _TelegramPlaylistsScreenState();
}

class _TelegramPlaylistsScreenState extends State<TelegramPlaylistsScreen> {
  late Stream<Map<int, List<Map<String, dynamic>>>> _results;
  final Map<int, Future<String>> _titles = {};
  late final Future<List<Map<String, dynamic>>> _savedPlaylists;
  final _searchController = TextEditingController();
  String _search = '';
  String? _selectedName;
  List<Map<String, dynamic>>? _selectedTracks;
  bool _syncWasRunning = false;

  void _onSyncChanged() {
    final running = TelegramSyncJob.shared.running;
    if (_syncWasRunning && !running && mounted) _refresh();
    _syncWasRunning = running;
  }

  void _clearSearch() {
    _searchController.clear();
    _search = '';
  }

  @override
  void dispose() {
    TelegramSyncJob.shared.removeListener(_onSyncChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _syncWasRunning = TelegramSyncJob.shared.running;
    TelegramSyncJob.shared.addListener(_onSyncChanged);
    _results = _load(refresh: widget.initialRefresh);
    _savedPlaylists = PlaylistStore(directory: widget.cacheDirectory).load();
  }

  Stream<MusicGroups> _load({bool refresh = false}) {
    final request = widget.request ?? TelegramClient.shared.request;
    return TelegramLibraryCache(
      request: request,
      library: widget.library ?? TelegramMusicLibrary(request: request),
      directory: widget.cacheDirectory,
    ).loadSelected();
  }

  Future<String> _title(int id) => _titles.putIfAbsent(id, () async {
    try {
      final chat = await (widget.request ?? TelegramClient.shared.request)({
        '@type': 'getChat',
        'chat_id': id,
      });
      final title = chat['title'];
      return title is String && title.trim().isNotEmpty ? title : 'Playlist';
    } catch (_) {
      return 'Playlist';
    }
  });

  void _refresh() => setState(() {
    _titles.clear();
    _results = _load(refresh: true);
  });

  void _openTracks(String name, List<Map<String, dynamic>> tracks) {
    if (widget.sheetMode) {
      setState(() {
        _clearSearch();
        _selectedName = name;
        _selectedTracks = tracks;
      });
      return;
    }
    final screen = _TelegramTracksScreen(
      name: name,
      tracks: tracks,
      request: widget.request ?? TelegramClient.shared.request,
      onPlay: widget.onPlay,
      onDownload: widget.onDownload,
      onDownloadPlaylist: widget.onDownloadPlaylist,
      sheetMode: widget.sheetMode,
    );
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));
  }

  void _backToPlaylists() => setState(() {
    _clearSearch();
    _selectedName = null;
    _selectedTracks = null;
  });

  Widget _buildCategory(BuildContext context) => PopScope(
    canPop: _selectedTracks == null && widget.onCategoryBack == null,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) return;
      if (_selectedTracks != null) {
        _backToPlaylists();
      } else {
        widget.onCategoryBack?.call();
      }
    },
    child: StreamBuilder<MusicGroups>(
      stream: _results,
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const LibraryLoadingSkeleton();
        }
        if (snapshot.hasError) {
          return const ErrorToastNotice(
            message: 'Could not load Telegram music.',
          );
        }
        final seen = <String>{};
        final tracks = <Map<String, dynamic>>[];
        for (final group in snapshot.data!.values) {
          for (final track in group) {
            if (seen.add('${track['chat_id']}:${track['id']}')) {
              tracks.add(track);
            }
          }
        }
        final shown =
            _selectedTracks ?? (widget.category == 'All songs' ? tracks : null);
        if (shown != null) {
          return _TelegramTracksScreen(
            name: _selectedName ?? 'All songs',
            tracks: shown,
            request: widget.request ?? TelegramClient.shared.request,
            onPlay: widget.onPlay,
            onDownload: widget.onDownload,
            onDownloadPlaylist: widget.onDownloadPlaylist,
            sheetMode: true,
            hideHeader:
                _selectedTracks == null && widget.category == 'All songs',
            onBack: _selectedTracks == null
                ? widget.onCategoryBack
                : _backToPlaylists,
            search: _search,
            searchController: _searchController,
            onSearchChanged: (value) => setState(() => _search = value),
          );
        }
        final groups = <String, List<Map<String, dynamic>>>{};
        for (final track in tracks) {
          final content = track['content'];
          final media = content is Map
              ? content['audio'] ?? content['document']
              : null;
          final data = media is Map ? media : const {};
          final raw = switch (widget.category) {
            'Artists' => data['performer'],
            'Albums' => data['album_title'] ?? data['album'],
            'Genres' => data['genre'],
            _ => null,
          };
          final name = raw is String && raw.trim().isNotEmpty
              ? raw.trim()
              : 'Unknown ${switch (widget.category) {
                  'Artists' => 'artist',
                  'Albums' => 'album',
                  _ => 'genre',
                }}';
          (groups[name] ??= []).add(track);
        }
        final names =
            groups.keys
                .where((name) => librarySearchMatches(name, _search))
                .toList()
              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        return Column(
          children: [
            ListTile(
              leading: IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onCategoryBack,
              ),
              title: Text(widget.category),
            ),
            Expanded(
              child: names.isEmpty
                  ? const Center(child: Text('No matching music.'))
                  : ListView.builder(
                      itemCount: names.length,
                      itemBuilder: (context, index) {
                        final name = names[index];
                        final items = groups[name]!;
                        return ListTile(
                          leading: PlaylistCover(
                            playlist: {'type': 'telegram', 'tracks': items},
                          ),
                          title: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${items.length} ${items.length == 1 ? 'track' : 'tracks'}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openTracks(name, items),
                        );
                      },
                    ),
            ),
            LibrarySearch(
              controller: _searchController,
              hint: 'Search ${widget.category.toLowerCase()}',
              onChanged: (value) => setState(() => _search = value),
            ),
          ],
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!widget.sheetMode) return _buildPlaylists(context);
    if (widget.category != 'Playlists') {
      return Material(
        color: Theme.of(context).colorScheme.surface,
        child: _buildCategory(context),
      );
    }
    final showingTracks = _selectedTracks != null;
    return PopScope(
      canPop: !showingTracks,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && showingTracks) _backToPlaylists();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage: showingTracks,
            child: TickerMode(
              enabled: !showingTracks,
              child: _buildPlaylists(context),
            ),
          ),
          if (showingTracks)
            _TelegramTracksScreen(
              name: _selectedName!,
              tracks: _selectedTracks!,
              request: widget.request ?? TelegramClient.shared.request,
              onPlay: widget.onPlay,
              onDownload: widget.onDownload,
              onDownloadPlaylist: widget.onDownloadPlaylist,
              sheetMode: true,
              onBack: _backToPlaylists,
              search: _search,
              searchController: _searchController,
              onSearchChanged: (value) => setState(() => _search = value),
            ),
        ],
      ),
    );
  }

  Widget _buildPlaylists(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.sheetMode
          ? Theme.of(context).colorScheme.surface
          : null,
      appBar: widget.sheetMode
          ? null
          : AppBar(
              title: const Text('Telegram playlists'),
              actions: [
                if (widget.onOpenLocal != null)
                  TextButton.icon(
                    onPressed: widget.onOpenLocal,
                    icon: const Icon(Icons.library_music_outlined),
                    label: const Text('Local'),
                  ),
                if (!widget.sheetMode)
                  IconButton(
                    onPressed: _refresh,
                    tooltip: 'Refresh',
                    icon: const Icon(Icons.refresh),
                  ),
              ],
            ),
      body: Column(
        children: [
          if (widget.sheetMode && !widget.hideHeader)
            ListTile(
              title: const Text('Telegram'),
              trailing: widget.onOpenLocal == null
                  ? null
                  : TextButton.icon(
                      onPressed: widget.onOpenLocal,
                      icon: const Icon(Icons.library_music_outlined),
                      label: const Text('Local'),
                    ),
            ),
          Expanded(
            child: StreamBuilder<Map<int, List<Map<String, dynamic>>>>(
              stream: _results,
              builder: (context, snapshot) {
                final groups = snapshot.data ?? {};
                final loading =
                    snapshot.connectionState != ConnectionState.done;
                final entries = groups.entries.toList();
                if (widget.sheetMode && loading && !snapshot.hasData) {
                  return const LibraryLoadingSkeleton();
                }
                return ListView(
                  padding: widget.sheetMode
                      ? EdgeInsets.zero
                      : const EdgeInsets.all(16),
                  children: [
                    if (loading && !widget.sheetMode)
                      const LinearProgressIndicator(),
                    if (groups.isEmpty && !loading && !snapshot.hasError)
                      ListTile(
                        title: Text(
                          widget.sheetMode
                              ? 'No cached music. Open Telegram playlists in Settings to sync.'
                              : 'No Telegram music found.',
                        ),
                      ),
                    if (snapshot.hasError)
                      const ErrorToastNotice(
                        message: 'Some music could not be loaded. Refresh to try again.',
                      ),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _savedPlaylists,
                      builder: (context, saved) {
                        if (saved.hasError) {
                          return const ErrorToastNotice(
                            message: 'Could not load saved playlists.',
                          );
                        }
                        final items = (saved.data ?? []).where(
                          (item) =>
                              item['type'] == 'telegram' &&
                              librarySearchMatches(
                                item['name']?.toString() ?? 'Playlist',
                                _search,
                              ),
                        );
                        if (items.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!widget.sheetMode) const Divider(),
                            if (!widget.sheetMode)
                              const Padding(
                                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                                child: Text('Your playlists'),
                              ),
                            for (final item in items)
                              Builder(
                                builder: (context) {
                                  final name =
                                      item['name']?.toString() ?? 'Playlist';
                                  final tracks =
                                      ((item['tracks'] as List?) ?? [])
                                          .whereType<Map>()
                                          .map(
                                            (e) => Map<String, dynamic>.from(e),
                                          )
                                          .toList();
                                  final tile = ListTile(
                                    leading: PlaylistCover(playlist: item),
                                    title: Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      '${tracks.length} ${tracks.length == 1 ? 'track' : 'tracks'}',
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _openTracks(name, tracks),
                                  );
                                  return widget.sheetMode
                                      ? tile
                                      : Card(child: tile);
                                },
                              ),
                          ],
                        );
                      },
                    ),
                    for (final entry in entries)
                      FutureBuilder<String>(
                        future: _title(entry.key),
                        builder: (context, title) {
                          final name = title.data ?? 'Loading playlist…';
                          if (_search.isNotEmpty &&
                              (title.data == null ||
                                  !librarySearchMatches(name, _search))) {
                            return const SizedBox.shrink();
                          }
                          final tile = ListTile(
                            leading: PlaylistCover(
                              playlist: {
                                'type': 'telegram',
                                'tracks': entry.value,
                              },
                            ),
                            title: widget.sheetMode && title.data == null
                                ? const Align(
                                    alignment: Alignment.centerLeft,
                                    child: LoadingSkeleton(
                                      width: 150,
                                      height: 14,
                                    ),
                                  )
                                : Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            subtitle: Text(
                              '${entry.value.length} ${entry.value.length == 1 ? 'track' : 'tracks'}${loading ? ' found' : ''}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: title.data == null
                                ? null
                                : () => _openTracks(name, entry.value),
                          );
                          return widget.sheetMode ? tile : Card(child: tile);
                        },
                      ),
                  ],
                );
              },
            ),
          ),
          if (widget.sheetMode)
            LibrarySearch(
              controller: _searchController,
              hint: 'Search playlists',
              onChanged: (value) => setState(() => _search = value),
            ),
        ],
      ),
    );
  }
}

class _TelegramTracksScreen extends StatelessWidget {
  const _TelegramTracksScreen({
    required this.name,
    required this.tracks,
    required this.request,
    this.onPlay,
    this.onDownload,
    this.onDownloadPlaylist,
    this.sheetMode = false,
    this.hideHeader = false,
    this.onBack,
    this.search = '',
    this.searchController,
    this.onSearchChanged,
  });
  final String search;
  final TextEditingController? searchController;
  final ValueChanged<String>? onSearchChanged;
  final bool sheetMode;
  final bool hideHeader;
  final VoidCallback? onBack;
  final String name;
  final List<Map<String, dynamic>> tracks;
  final TelegramRequest request;
  final Future<void> Function(List<Map<String, dynamic>>, int, String)? onPlay;
  final Future<void> Function(Map<String, dynamic>, String)? onDownload;
  final void Function(List<Map<String, dynamic>>, String)? onDownloadPlaylist;

  @override
  Widget build(BuildContext context) {
    final indices = List<int>.generate(tracks.length, (index) => index).where((
      index,
    ) {
      final content = tracks[index]['content'];
      final media = content is Map
          ? content['audio'] ?? content['document']
          : null;
      final data = media is Map ? media : const {};
      return librarySearchMatches(
        '${data['title'] ?? ''} ${data['file_name'] ?? ''} ${data['performer'] ?? ''}',
        search,
      );
    }).toList();
    final list = ListView.builder(
      itemCount: indices.length,
      itemBuilder: (context, position) {
        final index = indices[position];
        final content = tracks[index]['content'] as Map;
        final audio = content['audio'] ?? content['document'];
        final data = audio is Map ? audio : const {};
        final title = data['title'];
        final filename = data['file_name'];
        final artist = data['performer'];
        return ListTile(
          trailing: onDownload == null
              ? null
              : ListenableBuilder(
                  listenable: DownloadedTracks.shared,
                  builder: (context, _) =>
                      DownloadedTracks.shared.contains(
                        DownloadedTracks.keyFor(tracks[index]),
                      )
                      ? const SizedBox.shrink()
                      : IconButton(
                          tooltip: 'Download track',
                          icon: const Icon(Icons.download_outlined),
                          onPressed: () async {
                            try {
                              await onDownload!(tracks[index], name);
                            } catch (error) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  AppSnackBar(
                                    kind: AppNoticeKind.error,
                                    content: Text('Download failed: $error'),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                ),
          onTap: onPlay == null
              ? null
              : () async {
                  try {
                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    if (sheetMode) {
                      navigator.popUntil((route) => route.isFirst);
                      try {
                        await onPlay!(tracks, index, name);
                      } catch (error) {
                        TelegramPlaybackLog.record(
                          'Track selection failed type=${error.runtimeType}',
                        );
                        if (messenger.mounted) {
                          messenger.showSnackBar(
                            AppSnackBar(
                              kind: AppNoticeKind.error,
                              content: Text('Could not start playback: $error'),
                            ),
                          );
                        }
                      }
                    } else {
                      await onPlay!(tracks, index, name);
                      if (context.mounted) {
                        navigator.popUntil((route) => route.isFirst);
                      }
                    }
                  } catch (error) {
                    TelegramPlaybackLog.record(
                      'Track selection failed type=${error.runtimeType}',
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        AppSnackBar(
                          kind: AppNoticeKind.error,
                          content: Text('Could not start playback: $error'),
                        ),
                      );
                    }
                  }
                },
          leading: TelegramArtwork(message: tracks[index], request: request),
          title: Text(
            title is String && title.isNotEmpty
                ? title
                : filename is String && filename.isNotEmpty
                ? filename
                : 'Untitled track',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: artist is String && artist.isNotEmpty
              ? Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis)
              : null,
        );
      },
    );
    final downloadButton = onDownloadPlaylist == null
        ? null
        : IconButton(
            tooltip: 'Download playlist',
            icon: const Icon(Icons.download_for_offline_outlined),
            onPressed: () {
              onDownloadPlaylist!(tracks, name);
              ScaffoldMessenger.of(context).showSnackBar(
                AppSnackBar(
                  kind: AppNoticeKind.success,
                  content: Text('Playlist added to download queue'),
                ),
              );
            },
          );
    if (sheetMode) {
      return SafeArea(
        child: Column(
          children: [
            if (!hideHeader)
              ListTile(
                leading: IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: onBack ?? () => Navigator.pop(context),
                ),
                title: Text(name),
                trailing: downloadButton,
              ),
            Expanded(child: list),
            LibrarySearch(
              controller: searchController,
              hint: 'Search songs or artists',
              onChanged: onSearchChanged ?? (_) {},
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(name), actions: [?downloadButton]),
      body: list,
    );
  }
}
