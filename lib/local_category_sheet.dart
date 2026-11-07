import 'package:flutter/material.dart';

import 'playback_controller.dart';
import 'playlist_store.dart';
import 'playlist_cover.dart';
import 'library_search.dart';
import 'error_toast_notice.dart';

class LocalCategorySheet extends StatefulWidget {
  const LocalCategorySheet({
    super.key,
    required this.category,
    required this.tracks,
    required this.onPlay,
    this.playlists,
    this.onBack,
  });
  final String category;
  final List<LocalTrack> tracks;
  final Future<void> Function(List<LocalTrack>, int) onPlay;
  final Future<List<Map<String, dynamic>>>? playlists;
  final VoidCallback? onBack;
  @override
  State<LocalCategorySheet> createState() => _LocalCategorySheetState();
}

class _LocalCategorySheetState extends State<LocalCategorySheet> {
  late final Future<List<Map<String, dynamic>>> _playlists;
  List<LocalTrack>? selected;
  String? selectedName;
  final searchController = TextEditingController();
  String search = '';

  void _clearSearch() {
    searchController.clear();
    search = '';
  }

  void _back() {
    if (selected != null) {
      setState(() {
        selected = null;
        selectedName = null;
        _clearSearch();
      });
    } else if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.pop(context, true);
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _playlists = widget.playlists ?? PlaylistStore().load();
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<LocalTrack>>{};
    if (widget.category != 'Playlists') {
      for (final track in widget.tracks) {
        final raw = switch (widget.category) {
          'Artists' => track.artist,
          'Albums' => track.album,
          _ => track.genre,
        };
        final value = raw?.trim();
        final name = value == null || value.isEmpty || value == '<unknown>'
            ? 'Unknown'
            : value;
        (groups[name] ??= []).add(track);
      }
    }
    final matchingIndices = selected == null
        ? <int>[]
        : List<int>.generate(selected!.length, (i) => i)
              .where(
                (i) => librarySearchMatches(
                  '${selected![i].displayTitle} ${selected![i].displayArtist}',
                  search,
                ),
              )
              .toList();
    return PopScope(
      canPop: selected == null && widget.onBack == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height:
              (MediaQuery.sizeOf(context).height * .8 -
                      MediaQuery.viewInsetsOf(context).bottom)
                  .clamp(200.0, double.infinity),
          child: SafeArea(
            child: Column(
              children: [
                ListTile(
                  leading: IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: _back,
                  ),
                  title: Text(selectedName ?? widget.category),
                ),
                Expanded(
                  child: selected != null
                      ? selected!.isEmpty
                            ? const Center(
                                child: Text('No songs in this playlist.'),
                              )
                            : ListView.builder(
                                itemCount: matchingIndices.length,
                                itemBuilder: (context, index) {
                                  final originalIndex = matchingIndices[index];
                                  final song = selected![originalIndex];
                                  return ListTile(
                                    leading: PlaylistCover(
                                      playlist: {
                                        'type': 'local',
                                        'tracks': [
                                          {'path': song.path},
                                        ],
                                      },
                                    ),
                                    title: Text(
                                      song.displayTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      song.displayArtist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: () async {
                                      await widget.onPlay(
                                        selected!,
                                        selected!.indexOf(song),
                                      );
                                      if (context.mounted) {
                                        Navigator.pop(context);
                                      }
                                    },
                                  );
                                },
                              )
                      : widget.category == 'Playlists'
                      ? FutureBuilder<List<Map<String, dynamic>>>(
                          future: _playlists,
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return const ErrorToastNotice(
                                message: 'Could not load playlists.',
                              );
                            }
                            if (!snapshot.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            final items = snapshot.data!
                                .where(
                                  (item) =>
                                      item['type'] == 'local' &&
                                      librarySearchMatches(
                                        item['name']?.toString() ?? 'Playlist',
                                        search,
                                      ),
                                )
                                .toList();
                            if (items.isEmpty) {
                              return Center(
                                child: Text(
                                  search.isEmpty
                                      ? 'No local playlists yet.'
                                      : 'No playlists found.',
                                ),
                              );
                            }
                            return ListView.builder(
                              itemCount: items.length,
                              itemBuilder: (context, index) {
                                final item = items[index];
                                final stored = ((item['tracks'] as List?) ?? [])
                                    .whereType<Map>();
                                final current = {
                                  for (final track in widget.tracks)
                                    track.path: track,
                                };
                                final songs = <LocalTrack>[
                                  for (final row in stored)
                                    if (row['path'] is String &&
                                        (row['path'] as String).isNotEmpty)
                                      current[row['path']] ??
                                          LocalTrack(
                                            path: row['path'] as String,
                                            name:
                                                row['name']?.toString() ??
                                                'Local track',
                                            title: row['title'] as String?,
                                            artist: row['artist'] as String?,
                                            album: row['album'] as String?,
                                          ),
                                ];
                                final name =
                                    item['name']?.toString() ?? 'Playlist';
                                return ListTile(
                                  leading: PlaylistCover(playlist: item),
                                  title: Text(name),
                                  subtitle: Text(
                                    '${songs.length} ${songs.length == 1 ? 'song' : 'songs'}',
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => setState(() {
                                    selected = songs;
                                    selectedName = name;
                                    _clearSearch();
                                  }),
                                );
                              },
                            );
                          },
                        )
                      : Builder(
                          builder: (context) {
                            final names =
                                groups.keys
                                    .where(
                                      (name) =>
                                          librarySearchMatches(name, search),
                                    )
                                    .toList()
                                  ..sort(
                                    (a, b) => a.toLowerCase().compareTo(
                                      b.toLowerCase(),
                                    ),
                                  );
                            if (names.isEmpty) {
                              return const Center(
                                child: Text('No music found.'),
                              );
                            }
                            return ListView.builder(
                              itemCount: names.length,
                              itemBuilder: (context, index) {
                                final name = names[index];
                                final songs = groups[name]!;
                                return ListTile(
                                  leading: PlaylistCover(
                                    playlist: {
                                      'type': 'local',
                                      'tracks': [
                                        {'path': songs.first.path},
                                      ],
                                    },
                                  ),
                                  title: Text(name),
                                  subtitle: Text(
                                    '${songs.length} ${songs.length == 1 ? 'song' : 'songs'}',
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => setState(() {
                                    selected = songs;
                                    selectedName = name;
                                    _clearSearch();
                                  }),
                                );
                              },
                            );
                          },
                        ),
                ),
                LibrarySearch(
                  controller: searchController,
                  hint: selected != null
                      ? 'Search songs or artists'
                      : 'Search ${widget.category.toLowerCase()}',
                  onChanged: (value) => setState(() => search = value),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
