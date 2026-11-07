import 'package:flutter/material.dart';

import 'playback_controller.dart';
import 'playlist_store.dart';
import 'playlist_cover.dart';
import 'error_toast_notice.dart';

class LocalLibraryScreen extends StatelessWidget {
  const LocalLibraryScreen({
    super.key,
    required this.tracks,
    required this.onPlay,
    this.playlists,
    this.onOpenTelegram,
    this.onOpenQueue,
  });
  final List<LocalTrack> tracks;
  final Future<void> Function(List<LocalTrack>, int) onPlay;
  final Future<List<Map<String, dynamic>>>? playlists;
  final VoidCallback? onOpenTelegram;
  final VoidCallback? onOpenQueue;

  void openCategory(BuildContext context, String category) {
    switch (category) {
      case 'All songs':
        _showTracks(context, category, tracks, replace: true);
      case 'Artists':
        _showGroups(context, category, (track) => track.artist, replace: true);
      case 'Albums':
        _showGroups(context, category, (track) => track.album, replace: true);
      case 'Genres':
        _showGroups(context, category, (track) => track.genre, replace: true);
    }
  }

  void _showTracks(
    BuildContext context,
    String title,
    List<LocalTrack> songs, {
    bool replace = false,
  }) {
    final route = MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: songs.isEmpty
            ? const Center(child: Text('This playlist has no songs.'))
            : ListView.builder(
                itemCount: songs.length,
                itemBuilder: (context, index) => ListTile(
                  leading: PlaylistCover(
                    playlist: {
                      'type': 'local',
                      'tracks': [
                        {'path': songs[index].path},
                      ],
                    },
                  ),
                  title: Text(
                    songs[index].displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    songs[index].displayArtist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () async {
                    await onPlay(songs, index);
                    if (context.mounted) {
                      Navigator.popUntil(context, (route) => route.isFirst);
                    }
                  },
                ),
              ),
      ),
    );
    if (replace) {
      Navigator.pushReplacement(context, route);
    } else {
      Navigator.push(context, route);
    }
  }

  void _showGroups(
    BuildContext context,
    String title,
    String? Function(LocalTrack) field, {
    bool replace = false,
  }) {
    final groups = <String, List<LocalTrack>>{};
    for (final track in tracks) {
      final value = field(track)?.trim();
      final name = value == null || value.isEmpty || value == '<unknown>'
          ? 'Unknown'
          : value;
      (groups[name] ??= []).add(track);
    }
    final names = groups.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final route = MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView.builder(
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
              onTap: () => _showTracks(context, name, songs),
            );
          },
        ),
      ),
    );
    if (replace) {
      Navigator.pushReplacement(context, route);
    } else {
      Navigator.push(context, route);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Local music'),
      actions: [
        if (onOpenTelegram != null)
          TextButton.icon(
            onPressed: onOpenTelegram,
            icon: const Icon(Icons.send_outlined),
            label: const Text('Telegram'),
          ),
      ],
    ),
    body: ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.library_music_outlined),
          title: const Text('All songs'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showTracks(context, 'All songs', tracks),
        ),
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: const Text('Artists'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showGroups(context, 'Artists', (track) => track.artist),
        ),
        ListTile(
          leading: const Icon(Icons.album_outlined),
          title: const Text('Albums'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showGroups(context, 'Albums', (track) => track.album),
        ),
        ListTile(
          leading: const Icon(Icons.category_outlined),
          title: const Text('Genres'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showGroups(context, 'Genres', (track) => track.genre),
        ),
        if (onOpenQueue != null)
          ListTile(
            leading: const Icon(Icons.queue_music),
            title: const Text('Current queue'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpenQueue,
          ),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: playlists ?? PlaylistStore().load(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const ErrorToastNotice(
                message: 'Could not load playlists.',
              );
            }
            final items = (snapshot.data ?? [])
                .where((item) => item['type'] == 'local')
                .toList();
            if (items.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text('Playlists'),
                ),
                for (final item in items)
                  Builder(
                    builder: (context) {
                      final saved = ((item['tracks'] as List?) ?? [])
                          .whereType<Map>();
                      final byPath = {
                        for (final track in tracks) track.path: track,
                      };
                      final songs = <LocalTrack>[
                        for (final row in saved)
                          if (row['path'] is String &&
                              (row['path'] as String).isNotEmpty)
                            byPath[row['path']] ??
                                LocalTrack(
                                  path: row['path'] as String,
                                  name:
                                      row['name']?.toString() ?? 'Local track',
                                  title: row['title'] as String?,
                                  artist: row['artist'] as String?,
                                  album: row['album'] as String?,
                                  genre: row['genre'] as String?,
                                ),
                      ];
                      final name = item['name']?.toString() ?? 'Playlist';
                      return ListTile(
                        leading: PlaylistCover(playlist: item),
                        title: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${songs.length} ${songs.length == 1 ? 'song' : 'songs'}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showTracks(context, name, songs),
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}
