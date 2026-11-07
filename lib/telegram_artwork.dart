import 'dart:io';

import 'package:flutter/material.dart';

import 'telegram_music_library.dart';
import 'loading_skeleton.dart';

class TelegramArtwork extends StatefulWidget {
  const TelegramArtwork({
    super.key,
    required this.message,
    required this.request,
  });
  final Map<String, dynamic> message;
  final TelegramRequest request;

  @override
  State<TelegramArtwork> createState() => _TelegramArtworkState();
}

class _TelegramArtworkState extends State<TelegramArtwork> {
  late Future<String?> _path;
  late (Object?, Object?, Object?, Object?, Object?, Object?) _artworkKey;

  @override
  void initState() {
    super.initState();
    _artworkKey = _artworkIdentity(widget.message);
    _path = _load();
  }

  @override
  void didUpdateWidget(covariant TelegramArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextKey = _artworkIdentity(widget.message);
    if (_artworkKey != nextKey || oldWidget.request != widget.request) {
      _artworkKey = nextKey;
      _path = _load();
    }
  }

  Future<String?> _load() =>
      resolveTelegramArtwork(widget.message, widget.request);

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: _path,
    builder: (context, snapshot) => ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: snapshot.connectionState != ConnectionState.done
          ? const LoadingSkeleton()
          : snapshot.data == null
          ? const SizedBox(width: 48, height: 48, child: Icon(Icons.music_note))
          : Image.file(
              File(snapshot.data!),
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox(
                width: 48,
                height: 48,
                child: Icon(Icons.music_note),
              ),
            ),
    ),
  );
}

(Object?, Object?, Object?, Object?, Object?, Object?) _artworkIdentity(
  Map<String, dynamic> message,
) {
  final content = message['content'];
  final media = content is Map ? content['audio'] ?? content['document'] : null;
  final thumbnail = media is Map
      ? media['album_cover_thumbnail'] ?? media['thumbnail']
      : null;
  final file = thumbnail is Map ? thumbnail['file'] : null;
  final remote = file is Map ? file['remote'] : null;
  final local = file is Map ? file['local'] : null;
  return (
    message['chat_id'],
    message['id'],
    file is Map ? file['id'] : null,
    remote is Map ? remote['id'] : null,
    local is Map ? local['path'] : null,
    local is Map ? local['is_downloading_completed'] : null,
  );
}

Future<String?> resolveTelegramArtwork(
  Map<String, dynamic> message,
  TelegramRequest request,
) async {
  final content = message['content'];
  if (content is! Map) return null;
  final media = content['audio'] ?? content['document'];
  if (media is! Map) return null;
  final thumbnail = media['album_cover_thumbnail'] ?? media['thumbnail'];
  if (thumbnail is! Map || thumbnail['file'] is! Map) return null;
  final file = thumbnail['file'] as Map;
  final local = file['local'];
  if (local is Map &&
      local['is_downloading_completed'] == true &&
      local['path'] is String &&
      (local['path'] as String).isNotEmpty) {
    final path = local['path'] as String;
    if (await File(path).exists()) return path;
  }
  var id = file['id'];
  final remote = file['remote'];
  final remoteId = remote is Map ? remote['id'] : null;
  if (remoteId is String &&
      remoteId.isNotEmpty &&
      !remoteId.startsWith('http://') &&
      !remoteId.startsWith('https://')) {
    try {
      final resolved = await request({
        '@type': 'getRemoteFile',
        'remote_file_id': remoteId,
        'file_type': null,
      });
      if (resolved['id'] is int) id = resolved['id'];
    } catch (_) {
      // A current in-memory file ID may still be usable.
    }
  }
  if (id is! int) return null;
  try {
    final result = await request({
      '@type': 'downloadFile',
      'file_id': id,
      'priority': 1,
      'offset': 0,
      'limit': 0,
      'synchronous': true,
    });
    final downloaded = result['local'];
    if (downloaded is Map &&
        downloaded['is_downloading_completed'] == true &&
        downloaded['path'] is String &&
        (downloaded['path'] as String).isNotEmpty) {
      return downloaded['path'] as String;
    }
  } catch (_) {
    // Artwork is optional; keep the music icon when it can't be fetched.
  }
  return null;
}
