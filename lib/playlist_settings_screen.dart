import 'package:flutter/material.dart';

import 'app_snack_bar.dart';

import 'package:flutter/services.dart';

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'playlist_store.dart';
import 'telegram_playlist_picker.dart';
import 'playlist_cover.dart';
import 'loading_skeleton.dart';
import 'error_toast_notice.dart';

class PlaylistSettingsScreen extends StatefulWidget {
  const PlaylistSettingsScreen({
    super.key,
    this.onPlay,
    this.ensureTelegramSession,
  });
  final Future<void> Function(Map<String, dynamic> playlist, int index)? onPlay;
  final Future<bool> Function()? ensureTelegramSession;
  @override
  State<PlaylistSettingsScreen> createState() => _PlaylistSettingsScreenState();
}

class _PlaylistSettingsScreenState extends State<PlaylistSettingsScreen> {
  final store = PlaylistStore();
  List<Map<String, dynamic>> playlists = [];
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await store.load();
      if (mounted) {
        setState(() {
          playlists = items;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'Could not load playlists.';
          loading = false;
        });
      }
    }
  }

  Future<void> _create() async {
    final name = TextEditingController();
    var type = 'local';
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Create playlist'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Playlist name'),
              ),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Music source'),
                items: const [
                  DropdownMenuItem(value: 'local', child: Text('Local')),
                  DropdownMenuItem(value: 'telegram', child: Text('Telegram')),
                ],
                onChanged: (value) => update(() => type = value ?? 'local'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = name.text.trim();
                if (value.isNotEmpty) {
                  Navigator.pop(context, {'name': value, 'type': type});
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    if (!mounted || result == null) return;
    final updated = [
      ...playlists,
      {'name': result['name'], 'type': result['type'], 'tracks': <Object>[]},
    ];
    try {
      await store.save(updated);
      if (mounted) setState(() => playlists = updated);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            kind: AppNoticeKind.error,
            content: Text('Could not save playlist.'),
          ),
        );
      }
    }
  }

  Future<void> _editLocal(int index) async {
    final item = playlists[index];
    final existing = ((item['tracks'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    List<Map<String, dynamic>> songs;
    try {
      if (Platform.isAndroid) {
        final rows = await const MethodChannel('musicgram/library')
            .invokeListMethod<dynamic>('songs');
        songs = (rows ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else {
        final files = await FilePicker.pickFiles(type: FileType.audio);
        songs = files
            .where((f) => f.path != null)
            .map((f) => <String, dynamic>{'path': f.path, 'name': f.name})
            .toList();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            kind: AppNoticeKind.error,
            content: Text('Could not load local music: $e'),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    final selected = existing.map((e) => e['path']).whereType<String>().toSet();
    final result = await Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (context) => StatefulBuilder(
          builder: (context, update) => Scaffold(
            appBar: AppBar(
              title: Text(item['name']?.toString() ?? 'Playlist'),
              actions: [
                TextButton(
                  onPressed: () {
                    final combined = <String, Map<String, dynamic>>{
                      for (final track in existing)
                        if (track['path'] is String)
                          track['path'] as String: track,
                      for (final track in songs)
                        if (track['path'] is String)
                          track['path'] as String: track,
                    };
                    Navigator.pop(context, [
                      for (final entry in combined.entries)
                        if (selected.contains(entry.key)) entry.value,
                    ]);
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
            body: songs.isEmpty
                ? const Center(child: Text('No local music found.'))
                : ListView.builder(
                    itemCount: songs.length,
                    itemBuilder: (context, i) {
                      final song = songs[i];
                      final path = song['path'];
                      final title = song['title'];
                      return CheckboxListTile(
                        value: path is String && selected.contains(path),
                        title: Text(
                          title is String && title.trim().isNotEmpty
                              ? title
                              : song['name']?.toString() ?? 'Unknown track',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          song['artist']?.toString() ?? 'Unknown artist',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onChanged: path is! String
                            ? null
                            : (value) => update(() {
                                if (value == true) {
                                  selected.add(path);
                                } else {
                                  selected.remove(path);
                                }
                              }),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
    if (!mounted || result == null) return;
    final updated = List<Map<String, dynamic>>.of(playlists);
    updated[index] = {...item, 'tracks': result};
    try {
      await store.save(updated);
      if (mounted) setState(() => playlists = updated);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            kind: AppNoticeKind.error,
            content: Text('Could not save playlist.'),
          ),
        );
      }
    }
  }

  Future<void> _editTelegram(int index) async {
    final item = playlists[index];
    final existing = ((item['tracks'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final result = await Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (_) => TelegramPlaylistPicker(
          name: item['name']?.toString() ?? 'Playlist',
          initial: existing,
          ensureSession: widget.ensureTelegramSession,
        ),
      ),
    );
    if (!mounted || result == null) return;
    final updated = List<Map<String, dynamic>>.of(playlists);
    updated[index] = {...item, 'tracks': result};
    try {
      await store.save(updated);
      if (mounted) setState(() => playlists = updated);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            kind: AppNoticeKind.error,
            content: Text('Could not save playlist.'),
          ),
        );
      }
    }
  }

  Future<void> _rename(int index) async {
    final input = TextEditingController(
      text: playlists[index]['name']?.toString() ?? '',
    );
    String? chosenCover;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Edit playlist'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PlaylistCover(
                  size: 112,
                  playlist: {...playlists[index], 'cover': ?chosenCover},
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      final files = await FilePicker.pickFiles(
                        type: FileType.image,
                      );
                      if (files.isNotEmpty &&
                          files.first.path != null &&
                          context.mounted) {
                        update(() => chosenCover = files.first.path);
                      }
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          AppSnackBar(
                            kind: AppNoticeKind.error,
                            content: const Text('Could not select a cover.'),
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Change cover'),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: input,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Playlist name',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = input.text.trim();
                if (value.isNotEmpty) Navigator.pop(context, value);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    input.dispose();
    if (!mounted || value == null) return;
    try {
      final updated = List<Map<String, dynamic>>.of(playlists);
      String? cover;
      if (chosenCover != null) {
        final dir = Directory(
          '${(await getApplicationSupportDirectory()).path}/playlist_covers',
        );
        await dir.create(recursive: true);
        final destination = File(
          '${dir.path}/${DateTime.now().microsecondsSinceEpoch}.image',
        );
        await File(chosenCover!).copy(destination.path);
        cover = destination.path;
      }
      updated[index] = {...updated[index], 'name': value, 'cover': ?cover};
      await store.save(updated);
      if (mounted) setState(() => playlists = updated);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            kind: AppNoticeKind.error,
            content: Text('Could not rename playlist.'),
          ),
        );
      }
    }
  }

  Future<void> _deletePlaylist(int index) async {
    final item = playlists[index];
    final name = item['name']?.toString() ?? 'Playlist';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete playlist?'),
        content: Text('Delete "$name"? Your music files will be kept.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final updated = List<Map<String, dynamic>>.of(playlists)..remove(item);
    try {
      await store.save(updated);
      if (mounted) setState(() => playlists = updated);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            kind: AppNoticeKind.error,
            content: const Text('Could not delete playlist.'),
          ),
        );
      }
    }
  }

  void _openPlaylist(int playlistIndex) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => StatefulBuilder(
          builder: (context, update) {
            final item = playlists[playlistIndex];
            final tracks = ((item['tracks'] as List?) ?? [])
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
            final telegram = item['type'] == 'telegram';
            return Scaffold(
              appBar: AppBar(
                title: Text(item['name']?.toString() ?? 'Playlist'),
              ),
              floatingActionButton: FloatingActionButton.extended(
                onPressed: () async {
                  if (telegram) {
                    await _editTelegram(playlistIndex);
                  } else {
                    await _editLocal(playlistIndex);
                  }
                  if (context.mounted) update(() {});
                },
                icon: Icon(tracks.isEmpty ? Icons.add : Icons.edit_outlined),
                label: Text(tracks.isEmpty ? 'Add music' : 'Edit music'),
              ),
              body: tracks.isEmpty
                  ? const Center(
                      child: Text(
                        'No tracks in this playlist. Use the edit button to add some.',
                      ),
                    )
                  : ListView.builder(
                      itemCount: tracks.length,
                      itemBuilder: (context, index) {
                        final track = tracks[index];
                        final content = track['content'];
                        final media = telegram && content is Map
                            ? content['audio'] ?? content['document']
                            : track;
                        final data = media is Map ? media : const {};
                        final title = data['title'];
                        final filename = data['file_name'] ?? data['name'];
                        final artist = telegram
                            ? data['performer']
                            : data['artist'];
                        return ListTile(
                          leading: PlaylistCover(
                            playlist: {
                              'type': telegram ? 'telegram' : 'local',
                              'tracks': [track],
                            },
                          ),
                          title: Text(
                            title is String && title.trim().isNotEmpty
                                ? title
                                : filename?.toString() ?? 'Untitled track',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: artist is String && artist.isNotEmpty
                              ? Text(
                                  artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : null,
                          onTap: widget.onPlay == null
                              ? null
                              : () async {
                                  final play = widget.onPlay!;
                                  final messenger = ScaffoldMessenger.of(
                                    context,
                                  );
                                  try {
                                    await play(item, index);
                                  } catch (error) {
                                    if (messenger.mounted) {
                                      messenger.showSnackBar(
                                        AppSnackBar(
                                          kind: AppNoticeKind.error,
                                          content: Text(
                                            'Could not play track: $error',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                        );
                      },
                    ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Playlist settings')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: loading || error != null ? null : _create,
      icon: const Icon(Icons.add),
      label: const Text('Create playlist'),
    ),
    body: loading
        ? ListView.builder(
            itemCount: 5,
            itemBuilder: (_, _) => const ListTile(
              leading: LoadingSkeleton(),
              title: Align(
                alignment: Alignment.centerLeft,
                child: LoadingSkeleton(width: 160, height: 16),
              ),
              subtitle: Align(
                alignment: Alignment.centerLeft,
                child: LoadingSkeleton(width: 90, height: 12),
              ),
            ),
          )
        : error != null
        ? ErrorToastNotice(message: error!)
        : playlists.isEmpty
        ? const Center(child: Text('No playlists yet.'))
        : ListView.builder(
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final item = playlists[index];
              return ListTile(
                leading: PlaylistCover(playlist: item),
                title: Text(item['name']?.toString() ?? ''),
                subtitle: Text(
                  item['type'] == 'telegram' ? 'Telegram' : 'Local',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Edit playlist',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _rename(index),
                    ),
                    IconButton(
                      tooltip: 'Delete playlist',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deletePlaylist(index),
                    ),
                  ],
                ),
                onTap: () => _openPlaylist(index),
              );
            },
          ),
  );
}
